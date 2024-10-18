#ifndef RENDERER_H
#define RENDERER_H

#include "camera.hpp"
#include "engine.hpp"
#include <cstdint>

namespace renderer
{
struct EngineState {
    glm::vec3 LIGHT_POS;

    glm::vec3 OBJECT_POS;
    glm::vec3 OBJECT_ROTATION;
    float OBJ_SCALE;

    bool CLEAR_DEPTH_BUF, CLEAR_COLOR_BUF, CLEAR_STENCIL_BUF;

    glm::vec4 CLEAR_COLOR;

    float NEAR_PLANE, FAR_PLANE, FOV;

    uint32_t RENDER_WIDTH;
    uint32_t RENDER_HEIGHT;

    EngineState() {
        LIGHT_POS = glm::vec3(3.0f, 2.0f, 3.0f);

        OBJECT_POS = glm::vec3(0.0f);
        OBJECT_ROTATION = glm::vec3(0.0f);
        OBJ_SCALE = 1.0;

        CLEAR_COLOR_BUF = CLEAR_DEPTH_BUF =
            CLEAR_STENCIL_BUF = true;

        CLEAR_COLOR = glm::vec4(0.2f, 0.1f, 0.15f, 1.0f);

        NEAR_PLANE = 0.1f;
        FAR_PLANE = 100.0f;

    }
};

namespace camera {
    extern Camera CAMERA_STATE;
    extern Camera g_Camera;
}

extern EngineState ENGINE_STATE;
extern EngineState g_Engine;

constexpr static float ASPECT_RATIO = 16.0 / 9.0;

static unsigned int VIEWPORT_WIDTH = 1280;
static unsigned int VIEWPORT_HEIGHT = 720;

int init();
void update_state();
void render();
void terminate();


}

#endif