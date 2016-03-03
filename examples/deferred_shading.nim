import math, sequtils, strutils, sdl2, opengl, ../fancygl, glm

var hm = createFlatMap(128,64)
hm.DiamondSquare(64)

discard sdl2.init(INIT_EVERYTHING)

var windowsize = vec2f(1280,960)
var viewport = vec4f(0,0,1280,960)

let window = createWindow("SDL/OpenGL Skeleton", 100, 100, windowsize.x.cint, windowsize.y.cint, SDL_WINDOW_OPENGL) # SDL_WINDOW_MOUSE_CAPTURE
let context = window.glCreateContext()

# Initialize OpenGL
loadExtensions()

let
  crateTexture = loadTexture2DFromFile("crate.png")
  starTexture = loadTexture2DFromFile("star_symmetric_gray.png")

  hmVertices = hm.vertices.arrayBuffer(GL_STATIC_DRAW)
  hmNormals = hm.normals.arrayBuffer(GL_STATIC_DRAW)
  hmTexCoords = hm.texCoords.arrayBuffer(GL_STATIC_DRAW)
  hmIndices = hm.indices.elementArrayBuffer(GL_STATIC_DRAW)

  sphereVertices = uvSphereVertices(32,16).arrayBuffer
  sphereNormals = uvSphereNormals(32,16).arrayBuffer
  sphereIndices = uvSphereIndices(32,16).elementArrayBuffer
  sphereTexCoords = uvSphereTexCoords(32,16).arrayBuffer

  #sphereVertices  = cylinderVertices(32, 0).arrayBuffer
  #sphereNormals   = cylinderNormals(32, 0).arrayBuffer
  #sphereTexCoords = cylinderTexCoords(32).arrayBuffer
  #sphereIndices   = cylinderIndices(32).elementArrayBuffer

var hideNormals, hideDeferredShading, flatShading, wireframe: bool

declareFramebuffer(Fb1FramebufferType):
  depth = createEmptyDepthTexture2D(windowsize)
  color = createEmptyTexture2D(windowsize, GL_RGBA8)
  normal = createEmptyTexture2D(windowsize, GL_RGBA16F)

let fb1 = createFb1FramebufferType()

if 0 != glSetSwapInterval(-1):
  echo "glSetSwapInterval -1 not supported"
  echo sdl2.getError()
  if 0 != glSetSwapInterval(1):
    echo "but glSetSwapInterval 1 is ok"
  else:
    echo "even 1 is not ok"
    echo sdl2.getError()

glClearColor(0.0, 0.0, 0.0, 1.0)                  # Set background color to black and opaque
glClearDepth(1.0)                                 # Set background depth to farthest
glEnable(GL_DEPTH_TEST)                           # Enable depth testing for z-culling                          # Set the type of depth-test
glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST) # Nice perspective corrections


let projection_mat = perspective(45.0, windowsize.x / windowsize.y, 0.1, 1000.0)

const numLights = 500

var
  mousePos = vec2f(0)
  simulationTime = 0.0
  frameCounter = 0

  movement = vec3d(0,0,0)
  rotation = vec2d(PI/2,0)
  position = vec3d(0,0, hm[0,0] + 10 )

  lightPositions = createArrayBuffer[Vec3f](numLights, GL_DYNAMIC_DRAW)
  lightColors = createArrayBuffer[Vec3f](numLights, GL_DYNAMIC_DRAW)

mapWriteBufferBlock(lightColors):
  let maximum = lightColors.len - 1
  for i in 0 .. maximum:
    mappedBuffer[i] = vec3f(random(1.0).float32, random(1.0).float32, random(1.0).float32)

var
  effectOrigin = position.xy.vec2f
  effectStartTime = -100.0f


proc showNormals(mvp: Mat4d, positions: ArrayBuffer[Vec3f], normals: ArrayBuffer[Vec3f], length:float32 = 1, color:Vec3f = vec3f(1)) =

  shadingDsl(GL_POINTS):
    numVertices = normals.len.GLsizei

    uniforms:
      mvp
      normalColor = color
      scale = length

    attributes:
      pos = positions
      normal = normals

    vertexMain:
      """
      v_normal = normal;
      v_pos = pos;
      """

    vertexOut:
      "out vec3 v_normal"
      "out vec3 v_pos"

    geometryMain:
      "layout(line_strip, max_vertices=2) out"
      """
      gl_Position = mvp * vec4(v_pos[0], 1);
      EmitVertex();
      gl_Position = mvp * vec4(v_pos[0] + v_normal[0] * scale, 1);
      EmitVertex();
      """

    fragmentMain:
      """
      color.rgb = normalColor;
      """

proc render() =

  let time = simulationTime

  var view_mat = I4()

  view_mat = view_mat.translate( position )
  view_mat = view_mat.rotate( vec3d(0,0,1), rotation.y )
  view_mat = view_mat.rotate( vec3d(1,0,0), rotation.x )


  let movement_ws = (view_mat * vec4d(movement, 0)).xyz
  position = position + movement_ws

  view_mat = view_mat.inverse

  let lightDir_cs = (view_mat * vec3d(0.577).vec4d(0)).xyz.vec3f

  # Clear color and depth buffers
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  if wireframe:
    glPolygonMode( GL_FRONT_AND_BACK, GL_LINE )
  else:
    glPolygonMode( GL_FRONT_AND_BACK, GL_FILL )

  bindFramebuffer(fb1):
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)


    glEnable(GL_CULL_FACE)
    glCullFace(GL_BACK)
    glDepthFunc(GL_LEQUAL)

    var baseOffset = vec3f(0,0,0)
    baseOffset.x = floor(position.x / hm.w.float) * hm.w.float
    baseOffset.y = floor(position.y / hm.h.float) * hm.h.float

    shadingDsl(GL_TRIANGLES):
      numVertices = hmindices.len.GLsizei
      numInstances = 64

      uniforms:
        modelview = view_mat
        projection = projection_mat
        time
        crateTexture
        baseOffset
        lightDir_cs
        effectOrigin
        effectStartTime
        instanceSize = vec2f(hm.w.float32, hm.h.float32)
        flatShading

      attributes:
        indices = hmIndices
        pos = hmVertices
        texcoord = hmTexCoords
        normal = hmNormals

      vertexMain:
        """
        vec3 offset = vec3(gl_InstanceID % 8 - 4, gl_InstanceID / 8 - 4, 0) * vec3(instanceSize,1) + baseOffset;
        vec3 pos_ws = pos + offset;

        float effectLength = time - effectStartTime;
        float effectParameter = effectLength * 5.0 - length(pos_ws.xy - effectOrigin) * 0.2;
        float effect = cos(clamp(effectParameter, -3.14, 3.14)) + 1;

        pos_ws.z += effect * 10.0 / (effectLength + 1);

        v_texcoord = texcoord * instanceSize;
        v_eyepos = (modelview * vec4(pos_ws, 1)).xyz;
        v_normal = (modelview * vec4(normal,0)).xyz;
        """

      vertexOut:
        "out vec2 v_texcoord"
        "out vec3 v_eyepos"
        "out vec3 v_normal"

      geometryMain:
        "layout(triangle_strip, max_vertices=3) out"
        """
        if( flatShading ) {
          g_normal = normalize(cross(v_eyepos[1] - v_eyepos[0], v_eyepos[2] - v_eyepos[0]));
        }

        for( int i=0; i < 3; i++) {
          gl_Position = projection * vec4(v_eyepos[i], 1);
          g_texcoord = v_texcoord[i];
          if( !flatShading ) {
            g_normal = v_normal[i];
          }
          EmitVertex();
        }
        """


      geometryOut:
        "out vec2 g_texcoord"
        "out vec3 g_normal"

      fragmentMain:
        """
        color = texture(crateTexture, g_texcoord);
        normal.rgb = g_normal;
        """
    #end shadingDsl
  #end bindFramebuffer(fb1)

  glPolygonMode( GL_FRONT_AND_BACK, GL_FILL )

  var
    mvp = projection_mat * view_mat
    inverse_mvp = mvp

  inverse_mvp = inverse(inverse_mvp)

  if hideDeferredShading:

    shadingDsl(GL_TRIANGLES):
      numVertices = 3

      uniforms:
        tex = fb1.color
        depth = fb1.depth
        norm = fb1.normal
        time
        viewport
        texSize = fb1.color.size
        inverse_mvp
        border = 0.5f * viewport.zw

      fragmentMain:
        """
        vec2 texcoord = (texCoord * viewport.zw ) / texSize;
        gl_FragDepth = texture(depth, texcoord).x;
        vec4 worldpos = inverse_mvp * vec4( (gl_FragCoord.xy / viewport.zw) * 2 - vec2(1), gl_FragDepth * 2 - 1, 1 );
        worldpos /= worldpos.w;

        //int tile = int(gl_FragCoord.x) / 64 % 2  + 2 * (int(gl_FragCoord.y) / 64 % 2);
        int tile = int(gl_FragCoord.x < border.x) + int(gl_FragCoord.y < border.y) * 2;


        if( gl_FragDepth != 1 ) {
          switch(tile) {
          case 0:
            //color = worldpos - floor(worldpos);
            color = fract(worldpos);
            break;
          case 1:
            color = texture(tex, texcoord);
            break;
          case 2:
            //vec3 worldpos_dx = dFdx(worldpos.xyz);
            //vec3 worldpos_dy = dFdx(worldpos.xyz);
            //color.rgb = normalize(cross(worldpos_dx, worldpos_dy));
            color = texture(norm, texcoord).z * texture(tex, texcoord);
            break;
          case 3:
            color = texture(norm, texcoord);
            break;
          }
        }
        color.a = 1.0;
        """

  else:

    fb1.glname.bindRead

    glBlitFramebuffer(
      0,0, 1280, 960,
      0,0, 1280, 960,
      GL_DEPTH_BUFFER_BIT,
      GL_NEAREST
    )

    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0)
    glDepthMask(false)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE)
    glCullFace(GL_FRONT)
    glDepthFunc(GL_GEQUAL)

    mapWriteBufferBlock(lightPositions):
      let poslen = numLights
      for i in 0 .. < poslen:
        let
          distance = time * 30
          r = float32(float32(i) / numLights) * 500.0f
          alpha = distance / r
          x = cos(alpha).float32 * r
          y = sin(alpha).float32 * r
          z = hm[x,y] + 1.5f

        mappedBuffer[i] = vec3f(x, y, z)

    #### render lights ####
    shadingDsl(GL_TRIANGLES):
      numVertices = sphereIndices.len.GLsizei
      numInstances = numLights.GLsizei

      uniforms:
        normalMat = view_mat
        mvp
        inverse_mvp

        scale = 10
        lightDir_cs
        viewport

        color_tex = fb1.color
        depth_tex = fb1.depth
        normal_tex = fb1.normal

      attributes:
        indices = sphereIndices
        pos = sphereVertices
        normal = sphereNormals
        #texCoord = sphereTexCoords

        instanceData:
          offset = lightPositions
          col = lightColors

      vertexMain:
        """
        gl_Position = mvp * vec4(pos * scale + offset, 1);
        v_normal = (normalMat * vec4(normal,0)).xyz;
        v_col = col;
        //v_texCoord = texCoord;
        v_lightPos = offset;
        """

      vertexOut:
        "out vec3 v_normal"
        "out vec3 v_col"
        "out vec3 v_lightPos"

      fragmentMain:
        """
        vec2 texcoord = (gl_FragCoord.xy - viewport.xy) / viewport.zw;

        float depth = texture(depth_tex, texcoord).x * 2 - 1;
        vec3 diffuse = texture(color_tex, texcoord).rgb * 2;
        vec3 normal = texture(normal_tex, texcoord).xyz;

        vec4 worldpos = inverse_mvp * vec4( texcoord * 2 - vec2(1), depth, 1 );
        worldpos /= worldpos.w;

        vec3 light_dir = v_lightPos - worldpos.xyz;
        float dist = length(light_dir);
        light_dir /= dist;
        light_dir = (normalMat * vec4(light_dir,0)).xyz;
        float factor1 = 1 - dist / scale;

        if( factor1 <= 0 ) {
          discard;
        }


        float factor2 = dot(normal, light_dir);

        color.rgb = v_col * diffuse * (factor1 * factor2);
        color.a = 1.0;
        """

    glDepthMask(false)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE)
    glCullFace(GL_BACK)
    glDisable(GL_DEPTH_TEST)

    shadingDsl(GL_POINTS):
      numVertices = numLights.GLsizei

      uniforms:
        star_tex = starTexture
        depth_tex = fb1.depth

        projection_mat
        view_mat

        scale = 3
        viewport

      attributes:
        a_pos = lightPositions
        a_color = lightColors

      vertexMain:
        """
        v_pos = a_pos;
        v_color = a_color;
        """

      vertexOut:
        "out vec3 v_pos"
        "out vec3 v_color"

      geometryMain:
        "layout(triangle_strip, max_vertices=4) out"
        """
        vec4 center_vs = view_mat * vec4(v_pos[0], 1);
        vec4 center_ndc = projection_mat * center_vs;
        center_ndc /= center_ndc.w;

        float scene_depth = texture(depth_tex, (center_ndc.xy + vec2(1))* 0.5).x * 2 - 1;
        float vertex_depth = center_ndc.z;

        if( abs(center_ndc.x) < 1 && abs(center_ndc.y) < 1 && scene_depth > vertex_depth) {

          g_color = v_color[0];

          gl_Position = projection_mat * (center_vs + vec4(-scale,-scale,0,0));
          texCoord = vec2( 0, 0);
          EmitVertex();

          gl_Position = projection_mat * (center_vs + vec4( scale,-scale,0,0));
          texCoord = vec2( 1, 0);
          EmitVertex();

          gl_Position = projection_mat * (center_vs + vec4(-scale, scale,0,0));
          texCoord = vec2( 0, 1);
          EmitVertex();

          gl_Position = projection_mat * (center_vs + vec4( scale, scale,0,0));
          texCoord = vec2( 1, 1);
          EmitVertex();
        }
        """

      geometryOut:
        "out vec2 texCoord"
        "out vec3 g_color"

      fragmentMain:
        """
        color = texture(star_tex, texCoord);
        color.rgb *= g_color;
        """

  glDepthMask(true)
  glDisable(GL_BLEND)
  glCullFace(GL_BACK)
  glEnable(GL_DEPTH_TEST)
  glDepthFunc(GL_LESS)

  if not hideNormals:
    showNormals(projection_mat * view_mat, sphereVertices, sphereNormals, 0.3f)

  glSwapWindow(window)

var
  evt = sdl2.defaultEvent
  runGame = true
  gamePaused = false
  simulationTimeOffset = 0.0
  fpsFrameCounter = 0
  fpsFrameCounterStartTime = 0.0

#captureMouse(SDL_True)

while runGame:
  let time = float64( getTicks() ) / 1000.0

  while pollEvent(evt):
    if evt.kind == QuitEvent:
      runGame = false
      break
    if evt.kind == KeyDown:
      let keyboardEvent = cast[KeyboardEventPtr](addr(evt))

      case keyboardEvent.keysym.scancode
      of SDL_SCANCODE_ESCAPE:
        runGame = false
        break

      of SDL_SCANCODE_SPACE:
        effectOrigin = position.xy.vec2f
        effectStartTime = simulationTime

      of SDL_SCANCODE_PAUSE:
        if gamePaused:
          gamePaused = false
          simulationTimeOffset = time - simulationTime
        else:
          gamePaused = true

      of SDL_SCANCODE_1:
        hideDeferredShading = not hideDeferredShading

      of SDL_SCANCODE_2:
        hideNormals = not hideNormals

      of SDL_SCANCODE_3:
        flatShading = not flatShading

      of SDL_SCANCODE_4:
        wireframe = not wireframe

      else:
        discard

    if evt.kind == MouseMotion:
      let mouseEvent = cast[MouseMotionEventPtr](addr(evt))

      mousePos.x = mouseEvent.x.float32
      mousePos.y = 960 - mouseEvent.y.float32
      rotation.x = clamp( rotation.x - mouseEvent.yrel.float / 128.0 , 0, PI )
      rotation.y = rotation.y - mouseEvent.xrel.float / 128.0


  var state = getKeyboardState()

  movement.z = (state[SDL_SCANCODE_D.int].float - state[SDL_SCANCODE_E.int].float) * 0.4
  movement.x = (state[SDL_SCANCODE_F.int].float - state[SDL_SCANCODE_S.int].float) * 0.4

  if not gamePaused:
    simulationTime = time - simulationTimeOffset

  if time - fpsFrameCounterStartTime >= 1:
    echo "FPS: ", fpsFrameCounter
    fpsFrameCounter = 0
    fpsFrameCounterStartTime = time

  render()
  fpsFrameCounter += 1
  frameCounter += 1
