import memfiles, glm, ../fancygl, sdl2, sdl2/ttf , opengl, strutils, math

include iqm

proc iqmFormatString(format : cuint) : string =
  case format
  of IQM_BYTE: "byte"
  of IQM_UBYTE: "ubyte"
  of IQM_SHORT: "short"
  of IQM_USHORT: "ushort"
  of IQM_INT: "int"
  of IQM_UINT: "uint"
  of IQM_HALF: "half"
  of IQM_FLOAT: "float"
  of IQM_DOUBLE: "double"
  else: "INVALID IQM FORMAT TAG: " & $format


proc iqmTypeString(t : cuint) : string =
  case t
  of IQM_POSITION:     "position"
  of IQM_TEXCOORD:     "texcoord"
  of IQM_NORMAL:       "normal"
  of IQM_TANGENT:      "tangent"
  of IQM_BLENDINDEXES: "blendindexes"
  of IQM_BLENDWEIGHTS: "blendweights"
  of IQM_COLOR:        "color"
  of IQM_CUSTOM:       "custom"
  else:                "INVALID IQM TYPE TAG: " & $t


type
  MeshData = object
    position : ArrayBuffer[Vec3f]
    texcoord : ArrayBuffer[Vec2f]
    normal   : ArrayBuffer[Vec3f]
    tangent  : ArrayBuffer[Vec4f]
    blendindexes : ArrayBuffer[Vec4[uint8]]
    blendweights : ArrayBuffer[Vec4[uint8]]

  Mesh = object
    data : ptr MeshData
    firstVertex : int
    numVertices : int

proc memptr[T](file:MemFile, offset: cuint) : ptr T = cast[ptr T](cast[int](file.mem) + offset.int)
proc memptr[T](file:MemFile, offset: cuint, num_elements: cuint) : DataView[T] =
  dataView[T]( cast[pointer](cast[int](file.mem) + offset.int), num_elements.int )

proc mkString[T](v : T, before,sep,after : string) : string =
  result = before
  var i = 0
  let last_i = v.len
  for x in v:
    result.add($x)
    if i != last_i:
      result.add(sep)
      i += 1

  result.add(after)

proc mkString[T](v : T, sep : string = ", ") : string =
  mkString(v, "", sep, "")

proc matrix(joint : iqmjoint) : Mat4d =
  result = I4()
  result = result.scale( vec3d(joint.scale[0], joint.scale[1], joint.scale[2]) )
  result = result.rotate( vec3d(joint.rotate[0], joint.rotate[1], joint.rotate[2]).normalize, 2 * arccos(joint.rotate[3]) )
  result = result.translate( vec3d( joint.translate[0], joint.translate[1], joint.translate[2] ) )

proc main() =
  discard sdl2.init(INIT_EVERYTHING)
  discard ttfinit()

  let window = createWindow("SDL/OpenGL Skeleton", 100, 100, 640, 480, SDL_WINDOW_OPENGL) # SDL_WINDOW_MOUSE_CAPTURE
  let context = window.glCreateContext()
  # Initialize OpenGL
  loadExtensions()

  let quadTexCoords = @[
    vec2f(0,0),
    vec2f(0,1),
    vec2f(1,0),
    vec2f(1,1)
  ].arrayBuffer

  let font = ttf.openFont("/usr/share/fonts/truetype/inconsolata/Inconsolata.otf", 32)

  var file = memfiles.open("mrfixit.iqm")
  defer:
    close(file)

  let hdr = memptr[iqmheader](file, 0)
  echo "version:   ", hdr.version

  var texts = newSeq[cstring](0)
  let textData = memptr[char](file, hdr.ofs_text, hdr.num_text)
  var i = 0
  while i < textData.len:
    texts.add(cast[cstring](textData[i].addr))
    while textData[i] != '\0':
      i += 1
    i += 1

  var textTextures = newSeq[Texture2D](texts.len)
  var textWidths = newSeq[cint](texts.len)
  i = 0
  for text in texts:
    echo "text: ", text
    if text[0] != '\0':
      let fg : sdl2.Color = (255.uint8, 255.uint8, 255.uint8, 255.uint8)
      let bg : sdl2.Color = (0.uint8, 0.uint8, 0.uint8, 255.uint8)
      let surface = font.renderTextShaded(text, fg, bg)
      textTextures[i] = surface.texture2D
      textWidths[i] = surface.w
      freeSurface(surface)
    else:
      textWidths[i] = -1

    i += 1

  echo "texts.len: ", texts.len
  echo "texts:     ", texts.mkString

  let vertexArrays = memptr[iqmvertexarray](file, hdr.ofs_vertexarrays, hdr.num_vertexarrays)

  template text(offset : cuint) : cstring =
    cast[cstring](cast[uint](file.mem) + hdr.ofs_text.uint + offset.uint)


  var meshData : MeshData

  echo "num vertex arrays: ", vertexArrays.len
  for va in vertexArrays:
    #echo "---- vertex array ----"
    #echo "type:   ", va.`type`.iqmTypeString
    #echo "format: ", va.format.iqmFormatString
    #echo "size:   ", va.size

    if va.`type` == IQM_POSITION and va.format == IQM_FLOAT and va.size == 3:
      echo "got positions"
      meshData.position = memptr[Vec3f](file, va.offset, hdr.num_vertexes).arrayBuffer

    if va.`type` == IQM_TEXCOORD and va.format == IQM_FLOAT and va.size == 2:
      echo "got texcoords"
      meshData.texcoord = memptr[Vec2f](file, va.offset, hdr.num_vertexes ).arrayBuffer

    if va.`type` == IQM_NORMAL and va.format == IQM_FLOAT and va.size == 3:
      echo "got normals"
      meshData.normal = memptr[Vec3f](file, va.offset, hdr.num_vertexes ).arrayBuffer

    if va.`type` == IQM_TANGENT and va.format == IQM_FLOAT and va.size == 4:
      echo "got tangents"
      meshData.tangent = memptr[Vec4f](file, va.offset, hdr.num_vertexes ).arrayBuffer

    if va.`type` == IQM_BLENDINDEXES and va.format == IQM_UBYTE and va.size == 4:
      echo "got blend indices"
      meshData.blendindexes = memptr[Vec4[uint8]](file, va.offset, hdr.num_vertexes ).arrayBuffer

    if va.`type` == IQM_BLENDWEIGHTS and va.format == IQM_UBYTE and va.size == 4:
      echo "got blend weights"
      meshData.blendweights = memptr[Vec4[uint8]](file, va.offset, hdr.num_vertexes ).arrayBuffer

  #end for

  echo "=========================================================================="
  let triangles = memptr[iqmtriangle](file, hdr.ofs_triangles, hdr.num_triangles)
  echo "triangles: ", triangles.len
  for tri in triangles.take(10):
    echo tri.vertex[0], ", ", tri.vertex[1], ", ", tri.vertex[2]

  let indices = memptr[uint32](file, hdr.ofs_triangles, hdr.num_triangles * 3).elementArrayBuffer

  echo "=========================================================================="
  let adjacencies = memptr[iqmadjacency](file, hdr.ofs_adjacency, hdr.num_triangles)
  echo "adjacencies: ", adjacencies.len
  for adj in adjacencies.take(10):
    echo adj.triangle[0], ", ", adj.triangle[1], ", ", adj.triangle[2]

  echo "=========================================================================="
  let meshes = memptr[iqmmesh](file, hdr.ofs_meshes, hdr.num_meshes)
  echo "meshes: ", meshes.len
  for mesh in meshes:
    echo "got iqm mesh:"
    echo "  name:           ", text(mesh.name)
    echo "  material:       ", mesh.material
    echo "  first_vertex:   ", mesh.first_vertex
    echo "  num_vertexes:   ", mesh.num_vertexes
    echo "  first_triangle: ", mesh.first_triangle
    echo "  num_triangles:  ", mesh.num_triangles

  echo "=========================================================================="
  let joints = memptr[iqmjoint](file, hdr.ofs_joints, hdr.num_joints)
  echo "joints: ", joints.len
  for joint in joints.take(10):
    echo "name:      ", text(joint.name)
    echo "parent:    ", joint.parent
    echo "translate: ", joint.translate.Vec3f
    echo "rotate:    ", joint.rotate.Vec4f
    echo "scale:     ", joint.scale.Vec3f

  var jointNameIndices = newSeq[int](joints.len)
  for i, joint in joints:
    let jointName = text(joint.name)
    var j = 0
    while jointName != texts[j]:
      j += 1
    jointNameIndices[i] = j

  echo "=========================================================================="

  let poses = memptr[iqmpose](file, hdr.ofs_poses, hdr.num_poses)
  echo "poses: ", poses.len
  for pose in poses.take(10):
    echo "parent:        ", pose.parent
    echo "mask:          ", pose.mask.int.toHex(8)
    echo "channeloffset: ", pose.channeloffset.mkString()
    echo "channelscale:  ", pose.channelscale.mkString()

  echo "=========================================================================="

  let anims = memptr[iqmanim](file, hdr.ofs_anims, hdr.num_anims)
  echo "anims: ", anims.len
  for anim in anims.take(10):
    echo "  name:        ", text(anim.name)
    echo "  first_frame: ", anim.first_frame
    echo "  num_frames:  ", anim.num_frames
    echo "  framerate:   ", anim.framerate
    echo "  flags:       ", anim.flags.int.toHex(8)

  echo "=========================================================================="

  #var
  #  t: Vec3f
  #  r: Quat4f
  #  s: Vec3f
  #
  #for joint in joints:
  #  t.x = p.channeloffset[0]; if p.mask and 0x01:  t.x += *framedata++ * p.channelscale[0];
  #  t.y = p.channeloffset[1]; if p.mask and 0x02:  t.y += *framedata++ * p.channelscale[1];
  #  t.z = p.channeloffset[2]; if p.mask and 0x04:  t.z += *framedata++ * p.channelscale[2];
  #  r.x = p.channeloffset[3]; if p.mask and 0x08:  r.x += *framedata++ * p.channelscale[3];
  #  r.y = p.channeloffset[4]; if p.mask and 0x10:  r.y += *framedata++ * p.channelscale[4];
  #  r.z = p.channeloffset[5]; if p.mask and 0x20:  r.z += *framedata++ * p.channelscale[5];
  #  r.w = p.channeloffset[6]; if p.mask and 0x40:  r.w += *framedata++ * p.channelscale[6];
  #  s.x = p.channeloffset[7]; if p.mask and 0x80:  s.x += *framedata++ * p.channelscale[7];
  #  s.y = p.channeloffset[8]; if p.mask and 0x100: s.y += *framedata++ * p.channelscale[8];
  #  s.z = p.channeloffset[9]; if p.mask and 0x200: s.z += *framedata++ * p.channelscale[9];
  #
  #  var bone_mat = I4()
  #  bone_mat = modelview_mat.translate( vec3d(0, 0, -17) )
  #  bone_mat = modelview_mat.rotate( rot )
  #  modelview_mat = modelview_mat.rotate( vec3d(0,1,0), time )
  #  modelview_mat = modelview_mat.rotate( vec3d(1,0,0), time )
  #
  #  Matrix3x4 m(rotate.normalize(), translate, scale);
  #  if(p.parent >= 0) frames[i*hdr.num_poses + j] = baseframe[p.parent] * m * inversebaseframe[j];
  #  else frames[i*hdr.num_poses + j] = m * inversebaseframe[j];


  let
    boxVertices = fancygl.boxVertices.arrayBuffer
    boxNormals  = fancygl.boxNormals.arrayBuffer
    boxColors   = fancygl.boxColors.arrayBuffer


  var
    runGame = true
    time = 0.0f
    projection_mat = perspective(45.0, 640 / 480, 0.1, 100.0)

  glEnable(GL_DEPTH_TEST)
  #glEnable(GL_CULL_FACE)
  #glCullFace(GL_FRONT)

  while runGame:
    #######################
    #### handle events ####
    #######################

    var evt = sdl2.defaultEvent
    while pollEvent(evt):

      if evt.kind == QuitEvent:
        runGame = false
        break

      if evt.kind == KeyDown:
        let keyboardEvent = cast[KeyboardEventPtr](addr(evt))

        case keyboardEvent.keysym.scancode
        of SDL_SCANCODE_ESCAPE:
          runGame = false

        else:
          discard

    ##################
    #### simulate ####
    ##################

    time = getTicks().float32 / 1000.0

    var view_mat = I4()
    view_mat = view_mat.translate( vec3d(0, 0, -17) )
    view_mat = view_mat.rotate( vec3d(0,0,1), time )
    view_mat = view_mat.rotate( vec3d(0,1,0), time )
    view_mat = view_mat.rotate( vec3d(1,0,0), time )

    ################
    #### render ####
    ################

    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    shadingDsl(GL_TRIANGLES):
      numVertices = GLsizei(triangles.len * 3)

      uniforms:
        modelview = view_mat
        projection = projection_mat
        time

      attributes:
        indices
        a_position = meshData.position
        a_texcoord = meshData.texcoord
        a_normal_os = meshData.normal
        a_tangent_os = meshData.tangent
        #blendindexes = meshData.blendindexes
        #blendweights = meshData.blendweights

      vertexMain:
        """
        gl_Position = projection * modelview * vec4(a_position, 1);
        v_texcoord = a_texcoord;
        v_normal_cs  = modelview * vec4(a_normal_os, 0);
        v_tangent_cs = modelview * a_tangent_os;
        """

      vertexOut:
        "out vec2 v_texcoord"
        "out vec4 v_normal_cs"
        "out vec4 v_tangent_cs"

      fragmentMain:
        """
        color.rgb = v_normal_cs.xyz;
        """

    glClear(GL_DEPTH_BUFFER_BIT)

    for joint in joints:
      var model_mat = joint.matrix

      var tmp = joint
      while tmp.parent >= 0:
        tmp = joints[tmp.parent]
        model_mat = tmp.matrix * model_mat

      shadingDsl(GL_TRIANGLES):
        numVertices = GLsizei(triangles.len * 3)

        uniforms:
          modelview = view_mat * model_mat
          projection = projection_mat
          time

        attributes:

          a_position_os = boxVertices
          a_normal_os   = boxNormals
          a_color    = boxColors

        vertexMain:
          """
          gl_Position = projection * modelview * vec4(a_position_os, 1);
          v_normal_cs  = modelview * vec4(a_normal_os, 0);
          v_color      = a_color;
          """

        vertexOut:
          "out vec4 v_normal_cs"
          "out vec3 v_color"

        fragmentMain:
          """
          color.rgb = v_color * v_normal_cs.z;
          """

    glClear(GL_DEPTH_BUFFER_BIT)

    for i, joint in joints:
      let textIndex = jointNameIndices[i]

      var model_mat = joint.matrix
      var tmp = joint
      while tmp.parent >= 0:
        tmp = joints[tmp.parent]
        model_mat = tmp.matrix * model_mat

      var pos = projection_mat * view_mat * model_mat * vec4d(0,0,0,1)
      pos /= pos.w

      let
        x = 16.0f
        y = textIndex.float32 * 16.0f
        w = textWidths[textIndex].float32 * 0.5f
        h = 16.0f

      shadingDsl(GL_TRIANGLE_STRIP):
        numVertices = 4

        uniforms:
          rectPos = vec2f(pos.xy) * vec2f(320,240)
          rectSize = vec2f(w,h)
          viewSize = vec2f(640,480)
          tex = textTextures[textIndex]

        attributes:
          a_texcoord = quadTexCoords

        vertexMain:
          """
          gl_Position = vec4( (rectPos + a_texcoord * rectSize) / (viewSize * 0.5f), 0, 1);
          v_texcoord = vec2(a_texcoord.x, 1.0 - a_texcoord.y);
          """

        vertexOut:
          "out vec2 v_texcoord"

        fragmentMain:
          """
          color = texture(tex, v_texcoord);
          """

#    for i, texture in textTextures:
#      if textWidths[i] > 0:
#        let
#          x = 16.0f
#          y = i.float32 * 16.0f
#          w = textWidths[i].float32 * 0.5f
#          h = 16.0f
#
#        shadingDsl(GL_TRIANGLE_STRIP):
#          numVertices = 4
#
#          uniforms:
#            rectPos = vec2f(x,y)
#            rectSize = vec2f(w,h)
#            viewSize = vec2f(640,480)
#            tex = textTextures[i]
#
#          attributes:
#            a_texcoord = quadTexCoords
#
#          vertexMain:
#            """
#            gl_Position = vec4( (rectPos + a_texcoord * rectSize) / (viewSize * 0.5f) - vec2(1), 0, 1);
#            gl_Position.y *= -1;
#            v_texcoord = vec2(a_texcoord.x, a_texcoord.y);
#            """
#
#          vertexOut:
#            "out vec2 v_texcoord"
#
#          fragmentMain:
#            """
#            color = texture(tex, v_texcoord);
#            """


    window.glSwapWindow()



#end main

main()






