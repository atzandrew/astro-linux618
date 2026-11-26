/*
 * gpufill: raw GPU cost of compositor-like passes on panfrost, offscreen
 * (EGL on the render node via GBM, no display), so it runs next to KWin.
 * Each test draws full-screen quads into a W x H RGBA8 texture FBO,
 * sampling a source texture, and times N frames with glFinish.
 *   gpufill [W H [FRAMES [CARD]]]  default 1080 2340 60
 * With CARD (a KMS node, e.g. /dev/dri/card0) the target is a GBM surface
 * on that device with SCANOUT|RENDERING, as KWin's output buffers
 * (mediatek-drm allocates, panfrost renders through kmsro).
 * Tests: clear only; 1 textured quad (copy); 1 quad rotated 90 degrees
 * (KWin's landscape-on-portrait); 4 blended layers (wallpaper + 3 windows);
 * then the same quads sampling a client-style buffer: a linear GBM bo on
 * the render node imported as a dmabuf EGLImage (how KWin samples Wayland
 * clients' buffers).
 * astro-linux618 docs/frame-pacing.md.
 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <gbm.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[512];
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		fprintf(stderr, "shader: %s\n", log);
		exit(1);
	}
	return s;
}

static const char *vs =
	"#version 300 es\n"
	"in vec2 pos; uniform mat2 rot; out vec2 uv;\n"
	"void main() { uv = (rot * pos) * 0.5 + 0.5; gl_Position = vec4(pos, 0.0, 1.0); }\n";
static const char *fs_cm =
	"#version 300 es\nprecision highp float;\n"
	"in vec2 uv; uniform sampler2D tex; uniform float alpha; out vec4 o;\n"
	"vec3 lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }\n"
	"vec3 enc(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }\n"
	"void main() { vec3 c = lin(texture(tex, uv).rgb); c = mat3(0.9,0.05,0.05, 0.05,0.9,0.05, 0.05,0.05,0.9) * c; o = vec4(enc(c), alpha); }\n";
static const char *fs =
	"#version 300 es\nprecision mediump float;\n"
	"in vec2 uv; uniform sampler2D tex; uniform float alpha; out vec4 o;\n"
	"void main() { o = vec4(texture(tex, uv).rgb, alpha); }\n";

int main(int argc, char **argv)
{
	int W = argc > 2 ? atoi(argv[1]) : 1080, H = argc > 2 ? atoi(argv[2]) : 2340;
	int N = argc > 3 ? atoi(argv[3]) : 60;
	const char *card = argc > 4 ? argv[4] : NULL;
	int fd = open(card ? card : "/dev/dri/renderD128", O_RDWR);
	struct gbm_device *gbm = fd >= 0 ? gbm_create_device(fd) : NULL;
	if (!gbm) { perror("render node"); return 1; }
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd =
		(void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy = gpd(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	EGLint maj, min;
	if (!eglInitialize(dpy, &maj, &min)) { fprintf(stderr, "eglInitialize\n"); return 1; }
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint cattr[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
			   EGL_SURFACE_TYPE, card ? EGL_WINDOW_BIT : EGL_PBUFFER_BIT,
			   EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
			   EGL_ALPHA_SIZE, 0, EGL_NONE };
	EGLConfig cfgs[64], cfg = NULL; EGLint n;
	eglChooseConfig(dpy, cattr, cfgs, 64, &n);
	for (int i = 0; i < n && card; i++) {
		EGLint id;
		eglGetConfigAttrib(dpy, cfgs[i], EGL_NATIVE_VISUAL_ID, &id);
		if (id == GBM_FORMAT_XRGB8888) { cfg = cfgs[i]; break; }
	}
	if (!cfg) cfg = cfgs[0];
	EGLint ctxa[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxa);
	struct gbm_surface *gs = NULL;
	EGLSurface surf = EGL_NO_SURFACE;
	if (card) {
		gs = gbm_surface_create(gbm, W, H, GBM_FORMAT_XRGB8888,
					GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
		if (!gs) { perror("gbm_surface_create"); return 1; }
		surf = eglCreateWindowSurface(dpy, cfg, (EGLNativeWindowType)gs, NULL);
		if (surf == EGL_NO_SURFACE) { fprintf(stderr, "window surface 0x%x\n", eglGetError()); return 1; }
	}
	if (!eglMakeCurrent(dpy, surf, surf, ctx)) {
		fprintf(stderr, "make current failed\n"); return 1;
	}
	printf("%s / %s, target %dx%d %s, %d frames per test\n",
	       glGetString(GL_RENDERER), glGetString(GL_VERSION), W, H,
	       card ? "GBM scanout surface" : "panfrost texture", N);

	/* target texture + FBO */
	GLuint dst, fbo, src;
	glGenTextures(1, &dst);
	glBindTexture(GL_TEXTURE_2D, dst);
	glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, W, H);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, dst, 0);
	if (card)
		glBindFramebuffer(GL_FRAMEBUFFER, 0);	/* the GBM scanout surface */
	/* source: a landscape H x W image (the rotated desktop), noise */
	unsigned *pix = malloc((size_t)W * H * 4);
	for (size_t i = 0; i < (size_t)W * H; i++)
		pix[i] = (unsigned)rand() | 0xff000000u;
	glGenTextures(1, &src);
	glBindTexture(GL_TEXTURE_2D, src);
	glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, H, W);
	glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, H, W, GL_RGBA, GL_UNSIGNED_BYTE, pix);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	/* client-style source: linear GBM bo -> dmabuf -> EGLImage -> texture */
	GLuint img_tex = 0;
	{
		struct gbm_device *rg = gbm;
		int rfd = -1;
		if (card) {
			rfd = open("/dev/dri/renderD128", O_RDWR);
			rg = gbm_create_device(rfd);
		}
		uint64_t mod = DRM_FORMAT_MOD_LINEAR;
		struct gbm_bo *bo = gbm_bo_create_with_modifiers2(rg, H, W, GBM_FORMAT_ARGB8888,
								  &mod, 1, GBM_BO_USE_RENDERING);
		if (!bo) { perror("gbm_bo_create linear"); return 1; }
		int dfd = gbm_bo_get_fd(bo);
		EGLAttrib ia[] = {
			EGL_WIDTH, H, EGL_HEIGHT, W,
			EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_ARGB8888,
			EGL_DMA_BUF_PLANE0_FD_EXT, dfd,
			EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
			EGL_DMA_BUF_PLANE0_PITCH_EXT, gbm_bo_get_stride(bo),
			EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLAttrib)(mod & 0xffffffff),
			EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLAttrib)(mod >> 32),
			EGL_NONE };
		EGLImage im = eglCreateImage(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, ia);
		if (im == EGL_NO_IMAGE) { fprintf(stderr, "eglCreateImage 0x%x\n", eglGetError()); return 1; }
		PFNGLEGLIMAGETARGETTEXTURE2DOESPROC tgt =
			(void *)eglGetProcAddress("glEGLImageTargetTexture2DOES");
		glGenTextures(1, &img_tex);
		glBindTexture(GL_TEXTURE_2D, img_tex);
		tgt(GL_TEXTURE_2D, im);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		/* fill it once by rendering (as a GL client would) */
		GLuint f2; glGenFramebuffers(1, &f2);
		glBindFramebuffer(GL_FRAMEBUFFER, f2);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, img_tex, 0);
		glClearColor(0.3f, 0.6f, 0.9f, 1); glClear(GL_COLOR_BUFFER_BIT); glFinish();
		glBindFramebuffer(GL_FRAMEBUFFER, card ? 0 : fbo);
		glBindTexture(GL_TEXTURE_2D, src);
	}

	GLuint p = glCreateProgram();
	glAttachShader(p, shader(GL_VERTEX_SHADER, vs));
	glAttachShader(p, shader(GL_FRAGMENT_SHADER, fs));
	glBindAttribLocation(p, 0, "pos");
	glLinkProgram(p);
	glUseProgram(p);
	GLint urot = glGetUniformLocation(p, "rot"), ualpha = glGetUniformLocation(p, "alpha");
	GLuint pc = glCreateProgram();
	glAttachShader(pc, shader(GL_VERTEX_SHADER, vs));
	glAttachShader(pc, shader(GL_FRAGMENT_SHADER, fs_cm));
	glBindAttribLocation(pc, 0, "pos");
	glLinkProgram(pc);
	GLint urotc = glGetUniformLocation(pc, "rot"), ualphac = glGetUniformLocation(pc, "alpha");
	/* full-size offscreen target for partial passes (blur-like) */
	GLuint off, offfbo;
	glGenTextures(1, &off);
	glBindTexture(GL_TEXTURE_2D, off);
	glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, W, H);
	glGenFramebuffers(1, &offfbo);
	glBindFramebuffer(GL_FRAMEBUFFER, offfbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, off, 0);
	glClear(GL_COLOR_BUFFER_BIT);
	glBindFramebuffer(GL_FRAMEBUFFER, card ? 0 : fbo);
	glBindTexture(GL_TEXTURE_2D, src);
	float quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
	GLuint vbo, vao;
	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);
	glGenBuffers(1, &vbo);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);
	glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
	glEnableVertexAttribArray(0);
	glViewport(0, 0, W, H);
	const float ident[] = { 1, 0, 0, 1 }, rot90[] = { 0, 1, -1, 0 };

	struct { const char *name; int layers; const float *rot; int dmabuf; int cm; int partial; } t[] = {
		{ "clear only", 0, ident, 0, 0, 0 },
		{ "1 quad, same orientation", 1, ident, 0, 0, 0 },
		{ "1 quad, rotated 90", 1, rot90, 0, 0, 0 },
		{ "4 blended layers, rotated 90", 4, rot90, 0, 0, 0 },
		{ "dmabuf: 1 quad, rotated 90", 1, rot90, 1, 0, 0 },
		{ "dmabuf: 4 layers, rotated 90", 4, rot90, 1, 0, 0 },
		{ "colour transform: 4 layers", 4, rot90, 1, 1, 0 },
		{ "4 layers + 20 partial passes", 4, rot90, 1, 0, 20 },
	};
	for (unsigned k = 0; k < sizeof(t) / sizeof(t[0]); k++) {
		glBindTexture(GL_TEXTURE_2D, t[k].dmabuf ? img_tex : src);
		glUseProgram(t[k].cm ? pc : p);
		glUniformMatrix2fv(t[k].cm ? urotc : urot, 1, GL_FALSE, t[k].rot);
		GLint ua = t[k].cm ? ualphac : ualpha;
		for (int warm = 0; warm < 2; warm++) {
			double t0 = now();
			for (int f = 0; f < (warm ? N : 5); f++) {
				glClearColor(0.1f, 0.2f, 0.3f, 1);
				glClear(GL_COLOR_BUFFER_BIT);
				for (int l = 0; l < t[k].layers; l++) {
					if (l) { glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA); }
					glUniform1f(ua, l ? 0.8f : 1.0f);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				}
				glDisable(GL_BLEND);
				/*
				 * Blur-like partial passes: a 400x200 scissored quad into
				 * the full-size offscreen target, no clear (contents kept),
				 * each pass sampled by the next; then back to the output.
				 */
				for (int pp = 0; pp < t[k].partial; pp++) {
					glBindFramebuffer(GL_FRAMEBUFFER, offfbo);
					glEnable(GL_SCISSOR_TEST);
					glScissor(100 + pp * 10, 100, 400, 200);
					glBindTexture(GL_TEXTURE_2D, pp ? off : img_tex);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
					glDisable(GL_SCISSOR_TEST);
				}
				if (t[k].partial) {
					glBindFramebuffer(GL_FRAMEBUFFER, card ? 0 : fbo);
					glBindTexture(GL_TEXTURE_2D, img_tex);
				}
				if (card) {
					struct gbm_bo *bo;
					eglSwapBuffers(dpy, surf);
					bo = gbm_surface_lock_front_buffer(gs);
					glFinish();
					gbm_surface_release_buffer(gs, bo);
				} else {
					glFinish();
				}
			}
			double ms = (now() - t0) * 1000 / N;
			if (warm)
				printf("%-32s %6.2f ms/frame  (%.0f Mpix/s written)\n", t[k].name, ms,
				       (double)W * H * (t[k].layers ? t[k].layers : 1) / ms / 1e3);
		}
	}
	return 0;
}
