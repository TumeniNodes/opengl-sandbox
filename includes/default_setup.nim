# included from fancygl.nim

proc debugCallback(source: GLenum, `type`: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: cstring, userParam: pointer): void {. cdecl .} =
  if severity == GL_DEBUG_SEVERITY_NOTIFICATION:
    return


  echo "gl-debug-callback:"
  echo "  message: ", message

  stdout.write "  source: "
  case source
  of GL_DEBUG_SOURCE_API:
    echo "api"
  of GL_DEBUG_SOURCE_WINDOW_SYSTEM:
    echo "window system"
  of GL_DEBUG_SOURCE_SHADER_COMPILER:
    echo "shader compiler"
  of GL_DEBUG_SOURCE_THIRD_PARTY:
    echo "third party"
  of GL_DEBUG_SOURCE_APPLICATION:
    echo "application"
  of GL_DEBUG_SOURCE_OTHER:
    echo "other"
  else:
    echo "¿", int(source), "?"

  stdout.write "  type: "
  case `type`
  of GL_DEBUG_TYPE_ERROR:
    echo "error"
  of GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR:
    echo "deprecated behavior"
  of GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR:
    echo "undefined behavior"
  of GL_DEBUG_TYPE_PORTABILITY:
    echo "portability"
  of GL_DEBUG_TYPE_PERFORMANCE:
    echo "performance"
  of GL_DEBUG_TYPE_MARKER:
    echo "marker"
  of GL_DEBUG_TYPE_PUSH_GROUP:
    echo "push group"
  of GL_DEBUG_TYPE_POP_GROUP:
    echo "pop group"
  of GL_DEBUG_TYPE_OTHER:
    echo "other"
  else:
    echo "¿ ", `type`.int, " ?"

  echo "  id: ", id
  stdout.write "  severity: "
  case severity
  of GL_DEBUG_SEVERITY_LOW:
    echo "low"
  of GL_DEBUG_SEVERITY_MEDIUM:
    echo "medium"
  of GL_DEBUG_SEVERITY_HIGH:
    echo "high"
  of GL_DEBUG_SEVERITY_NOTIFICATION:
    echo "notification"
  else:
    echo "¿ ", severity.int, " ?"

proc enableDefaultDebugCallback*() =
  glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB)
  glDebugMessageCallbackARB(cast[GLdebugProcArb](debugCallback), nil);

proc defaultSetupInternal(windowsize: Vec2i; windowTitle: string): tuple[window: WindowPtr, context: GlContextPtr] =
  discard sdl2.init(INIT_EVERYTHING)
  discard
  if ttf_init():
    write stderr, getError()



  doAssert 0 == glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
  doAssert 0 == glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
  doAssert 0 == glSetAttribute(SDL_GL_CONTEXT_FLAGS        , SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG or SDL_GL_CONTEXT_DEBUG_FLAG)
  doAssert 0 == glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK , SDL_GL_CONTEXT_PROFILE_CORE)
  doAssert 0 == glSetAttribute(SDL_GL_STENCIL_SIZE         , 8)

  if getNumVideoDisplays() < 1:
    panic "no monitor detected, need at least one, but got: ", getNumVideoDisplays()

  let flags =
    if windowsize.x < 0:
      SDL_WINDOW_OPENGL or SDL_WINDOW_FULLSCREEN_DESKTOP
    else:
      SDL_WINDOW_OPENGL

  let posx = SDL_WINDOWPOS_UNDEFINED.cint
  let posy = SDL_WINDOWPOS_UNDEFINED.cint

  result.window = createWindow(windowTitle, posx, posy, windowsize.x, windowsize.y, flags)

  if result.window.isNil:
    panic sdl2.getError()

  result.context = result.window.glCreateContext()
  if result.context.isNil:
    panic sdl2.getError()

  #Initialize OpenGL
  loadExtensions()

  glPushDebugGroup(GL_DEBUG_SOURCE_APPLICATION, 1, 12, "defaultSetup");
  defer:
    glPopDebugGroup()


  echo "extensions loaded"
  enableDefaultDebugCallback()

  doAssert 0 == glMakeCurrent(result.window, result.context)

  if 0 != glSetSwapInterval(-1):
    stdout.write "late swap tearing not supported: "
    echo sdl2.getError()
    if 0 != glSetSwapInterval(1):
      echo "setting swap interval synchronized"
    else:
      stdout.write "even 1 (synchronized) is not supported: "
      echo sdl2.getError()


  glEnable(GL_DEPTH_TEST)


template defaultSetup*(windowsize: Vec2i = vec2i(-1, -1), windowTitle: string = nil): tuple[window: WindowPtr, context: GlContextPtr] =
  var name = if windowTitle.isNil: instantiationInfo().filename else: windowTitle
  name.removeSuffix(".nim")
  defaultSetupInternal(windowsize, name)
