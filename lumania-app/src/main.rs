mod settings;
mod theme;
mod update;

use gpui::{
    App, Application, Bounds, Context, Div, FontWeight, Window, WindowBounds,
    WindowOptions, div, prelude::*, px, rgb, rgba, size,
};
use settings::LumaniaSettings;
use theme::{AppTheme, hex_to_rgba};
use update::{UpdateManager, UpdateStatus};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActiveTab {
    Settings,
    Updates,
}

struct LumaniaAppView {
    tab: ActiveTab,
    theme: AppTheme,
    settings: LumaniaSettings,
    update_mgr: UpdateManager,
    save_status: Option<String>,
}

impl LumaniaAppView {
    fn new(cx: &mut Context<Self>) -> Self {
        let theme = AppTheme::load();
        let settings = LumaniaSettings::load();
        let update_mgr = UpdateManager::new();

        // Background worker: reacts to external wallpaper and theme switches in real time
        cx.spawn(async move |this, cx| {
            loop {
                smol::Timer::after(std::time::Duration::from_millis(300)).await;
                let new_theme = AppTheme::load();
                let res = this.update(cx, |view, cx| {
                    if view.theme.raw.wallpaper != new_theme.raw.wallpaper
                        || view.theme.raw.accent != new_theme.raw.accent
                        || view.theme.raw.complementary != new_theme.raw.complementary
                    {
                        view.theme = new_theme;
                        cx.notify();
                    }
                });
                if res.is_err() {
                    break;
                }
            }
        })
        .detach();

        Self {
            tab: ActiveTab::Settings,
            theme,
            settings,
            update_mgr,
            save_status: None,
        }
    }
}

impl Render for LumaniaAppView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let accent = self.theme.accent;
        let card_border = self.theme.card_border;
        let text_primary = self.theme.text_primary;
        let text_sec = self.theme.text_secondary;
        let active_tab = self.tab;

        div()
            .flex()
            .flex_col()
            .size_full()
            .bg(self.theme.window_bg)
            .text_color(text_primary)
            // ---- HEADER BAR ----
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .justify_between()
                    .px_6()
                    .py_4()
                    .border_b_1()
                    .border_color(card_border)
                    .bg(rgba(0x00000045))
                    // Left Brand: Celestial Moon Logo & App Title
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .gap_3()
                            // Celestial Moon Badge
                            .child(
                                div()
                                    .size_10()
                                    .rounded_2xl()
                                    .bg(rgba(0x00000040))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .relative()
                                    // Pure White Moon Crescent
                                    .child(
                                        div()
                                            .size_7()
                                            .rounded_full()
                                            .bg(rgb(0xffffff))
                                            .relative()
                                            .overflow_hidden()
                                            // Dark Mask Sphere carving the Moon shape
                                            .child(
                                                div()
                                                    .size_6()
                                                    .rounded_full()
                                                    .bg(self.theme.window_bg)
                                                    .absolute()
                                                    .top(px(-1.5))
                                                    .left(px(-3.5)),
                                            ),
                                    ),
                            )
                            // Title & Version
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .child(
                                        div()
                                            .flex()
                                            .flex_row()
                                            .items_center()
                                            .gap_2()
                                            .child(
                                                div()
                                                    .text_base()
                                                    .font_weight(FontWeight::BOLD)
                                                    .child("Lumania Shell"),
                                            )
                                            .child(
                                                div()
                                                    .text_xs()
                                                    .px_2()
                                                    .py_0p5()
                                                    .rounded_md()
                                                    .bg(card_border)
                                                    .text_color(accent)
                                                    .font_weight(FontWeight::MEDIUM)
                                                    .child(format!("v{}", self.update_mgr.current_version)),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(self.theme.text_muted)
                                            .child("Desktop Shell Companion"),
                                    ),
                            ),
                    )
                    // Right/Center Navigation Tabs
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .gap_1()
                            .p_1()
                            .rounded_xl()
                            .bg(rgba(0x00000045))
                            .border_1()
                            .border_color(card_border)
                            .child(
                                div()
                                    .id("tab-settings")
                                    .px_5()
                                    .py_1p5()
                                    .rounded_lg()
                                    .text_sm()
                                    .font_weight(FontWeight::MEDIUM)
                                    .cursor_pointer()
                                    .when(active_tab == ActiveTab::Settings, |s| {
                                        s.bg(accent).text_color(rgb(0x111111)).font_weight(FontWeight::BOLD)
                                    })
                                    .when(active_tab != ActiveTab::Settings, |s| {
                                        s.text_color(text_sec).hover(|h| h.bg(rgba(0xffffff0f)))
                                    })
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.tab = ActiveTab::Settings;
                                        cx.notify();
                                    }))
                                    .child("Settings"),
                            )
                            .child(
                                div()
                                    .id("tab-updates")
                                    .px_5()
                                    .py_1p5()
                                    .rounded_lg()
                                    .text_sm()
                                    .font_weight(FontWeight::MEDIUM)
                                    .cursor_pointer()
                                    .when(active_tab == ActiveTab::Updates, |s| {
                                        s.bg(accent).text_color(rgb(0x111111)).font_weight(FontWeight::BOLD)
                                    })
                                    .when(active_tab != ActiveTab::Updates, |s| {
                                        s.text_color(text_sec).hover(|h| h.bg(rgba(0xffffff0f)))
                                    })
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.tab = ActiveTab::Updates;
                                        cx.notify();
                                    }))
                                    .child("Updates"),
                            ),
                    ),
            )
            // ---- MAIN BODY VIEW ----
            .child(
                div()
                    .id("main-body-scroll")
                    .flex_1()
                    .p_6()
                    .overflow_y_scroll()
                    .child(match active_tab {
                        ActiveTab::Settings => self.render_settings_page(cx),
                        ActiveTab::Updates => self.render_updates_page(cx),
                    }),
            )
    }
}

impl LumaniaAppView {
    fn render_settings_page(&self, cx: &mut Context<Self>) -> Div {
        let accent = self.theme.accent;
        let card_bg = self.theme.card_bg;
        let card_border = self.theme.card_border;
        let text_sec = self.theme.text_secondary;
        let text_muted = self.theme.text_muted;
        let dyn_enabled = self.settings.dynamic_wallpaper_color;
        let mode = self.settings.wallpaper_color_mode.clone();
        let border_th = self.settings.border_thickness;
        let corner_style = self.settings.corner_style.clone();
        let corner_rad = self.settings.corner_radius;
        let island_w = self.settings.island_body_width;
        let instant_wp = self.settings.wallpaper_instant_switch;
        let thumbs_cnt = self.settings.wallpaper_max_visible_thumbs;

        div()
            .flex()
            .flex_col()
            .gap_5()
            // SECTION 1: Wallpaper & Color Engine
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_3()
                    .p_4()
                    .rounded_2xl()
                    .bg(card_bg)
                    .border_1()
                    .border_color(card_border)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .justify_between()
                            .items_center()
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .child(
                                        div()
                                            .text_sm()
                                            .font_weight(FontWeight::BOLD)
                                            .child("Dynamic Wallpaper Color Engine"),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(text_muted)
                                            .child("Real-time GPU/Rust color extraction from active desktop background (<2ms)"),
                                    ),
                            )
                            // Toggle switch (Real-time auto save)
                            .child(
                                div()
                                    .id("dyn-color-switch")
                                    .w(px(52.))
                                    .h(px(28.))
                                    .rounded_full()
                                    .p_1()
                                    .cursor_pointer()
                                    .when(dyn_enabled, |s| s.bg(accent))
                                    .when(!dyn_enabled, |s| s.bg(rgba(0xffffff20)))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.settings.dynamic_wallpaper_color =
                                            !this.settings.dynamic_wallpaper_color;
                                        let _ = this.settings.save();
                                        cx.notify();
                                    }))
                                    .child(
                                        div()
                                            .size(px(20.))
                                            .rounded_full()
                                            .bg(rgb(0xffffff))
                                            .when(dyn_enabled, |s| s.ml(px(24.)))
                                            .when(!dyn_enabled, |s| s.ml(px(0.))),
                                    ),
                            ),
                    )
                    // Color Mode selector (Accent vs Complementary)
                    .when(dyn_enabled, |s| {
                        s.child(
                            div()
                                .flex()
                                .flex_row()
                                .items_center()
                                .justify_between()
                                .pt_2()
                                .border_t_1()
                                .border_color(rgba(0xffffff0a))
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(text_sec)
                                        .child("Color Palette Mode"),
                                )
                                .child(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .gap_1()
                                        .p_1()
                                        .rounded_lg()
                                        .bg(rgba(0x00000030))
                                        .child(
                                            self.render_mode_pill(
                                                "Accent (Vibrant)",
                                                mode == "accent",
                                                "accent",
                                                cx,
                                            ),
                                        )
                                        .child(
                                            self.render_mode_pill(
                                                "Complementary (180°)",
                                                mode == "complementary",
                                                "complementary",
                                                cx,
                                            ),
                                        ),
                                ),
                        )
                    })
                    // Manual Color swatches when dynamic color is OFF
                    .when(!dyn_enabled, |s| {
                        let active_hex = self.settings.border_color.clone();
                        s.child(
                            div()
                                .flex()
                                .flex_row()
                                .items_center()
                                .justify_between()
                                .pt_2()
                                .border_t_1()
                                .border_color(rgba(0xffffff0a))
                                .child(
                                    div()
                                        .text_xs()
                                        .text_color(text_sec)
                                        .child("Manual Border Tone"),
                                )
                                .child(
                                    div()
                                        .flex()
                                        .flex_row()
                                        .gap_2()
                                        .children([
                                            "#ba5f58", "#58a8ba", "#9d7cd8", "#41a6b5", "#e0af68",
                                            "#7aa2f7",
                                        ]
                                        .into_iter()
                                        .enumerate()
                                        .map(|(ix, hex)| {
                                            let is_sel = active_hex == hex;
                                            let c = hex_to_rgba(hex, 1.0);
                                            let h_owned = hex.to_string();
                                            div()
                                                .id(("swatch", ix))
                                                .size_6()
                                                .rounded_full()
                                                .bg(c)
                                                .cursor_pointer()
                                                .border_2()
                                                .when(is_sel, |b| b.border_color(rgb(0xffffff)))
                                                .when(!is_sel, |b| b.border_color(rgba(0x00000040)))
                                                .on_click(cx.listener(move |this, _, _, cx| {
                                                    this.settings.border_color = h_owned.clone();
                                                    let _ = this.settings.save();
                                                    cx.notify();
                                                }))
                                        })),
                                ),
                        )
                    }),
            )
            // SECTION 2: Screen Frame & Corner Geometry
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_3()
                    .p_4()
                    .rounded_2xl()
                    .bg(card_bg)
                    .border_1()
                    .border_color(card_border)
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::BOLD)
                            .child("Screen Frame & Geometry"),
                    )
                    // Border Thickness (Real-time auto save)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("Screen Border Thickness"),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .gap_1()
                                    .children([0, 3, 5, 8, 10].into_iter().map(|val| {
                                        let sel = border_th == val;
                                        div()
                                            .id(("thickness", val))
                                            .px_3()
                                            .py_1()
                                            .rounded_md()
                                            .text_xs()
                                            .font_weight(FontWeight::MEDIUM)
                                            .cursor_pointer()
                                            .when(sel, |b| b.bg(accent).text_color(rgb(0x111111)))
                                            .when(!sel, |b| {
                                                b.bg(rgba(0xffffff0f))
                                                    .text_color(text_sec)
                                                    .hover(|h| h.bg(rgba(0xffffff1a)))
                                            })
                                            .on_click(cx.listener(move |this, _, _, cx| {
                                                this.settings.border_thickness = val;
                                                let _ = this.settings.save();
                                                cx.notify();
                                            }))
                                            .child(format!("{}px", val))
                                    })),
                            ),
                    )
                    // Corner Style: Squircle vs Arc (Real-time auto save)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("Corner Curvature Model"),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .gap_1()
                                    .child(
                                        self.render_style_pill(
                                            "Squircle (iOS Continuous)",
                                            corner_style == "squircle",
                                            "squircle",
                                            cx,
                                        ),
                                    )
                                    .child(
                                        self.render_style_pill(
                                            "Arc (Geometric Fillet)",
                                            corner_style == "arc",
                                            "arc",
                                            cx,
                                        ),
                                    ),
                            ),
                    )
                    // Corner Radius (Real-time auto save)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("Corner Fillet Radius"),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .gap_1()
                                    .children([8, 12, 16, 20, 24].into_iter().map(|rad| {
                                        let sel = corner_rad == rad;
                                        div()
                                            .id(("radius", rad))
                                            .px_3()
                                            .py_1()
                                            .rounded_md()
                                            .text_xs()
                                            .font_weight(FontWeight::MEDIUM)
                                            .cursor_pointer()
                                            .when(sel, |b| b.bg(accent).text_color(rgb(0x111111)))
                                            .when(!sel, |b| {
                                                b.bg(rgba(0xffffff0f))
                                                    .text_color(text_sec)
                                                    .hover(|h| h.bg(rgba(0xffffff1a)))
                                            })
                                            .on_click(cx.listener(move |this, _, _, cx| {
                                                this.settings.corner_radius = rad;
                                                let _ = this.settings.save();
                                                cx.notify();
                                            }))
                                            .child(format!("{}px", rad))
                                    })),
                            ),
                    )
                    // Dynamic Island Width (Real-time auto save)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("Dynamic Island Idle Width"),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .gap_1()
                                    .children([180, 206, 230, 260].into_iter().map(|w| {
                                        let sel = island_w == w;
                                        div()
                                            .id(("island-w", w))
                                            .px_3()
                                            .py_1()
                                            .rounded_md()
                                            .text_xs()
                                            .font_weight(FontWeight::MEDIUM)
                                            .cursor_pointer()
                                            .when(sel, |b| b.bg(accent).text_color(rgb(0x111111)))
                                            .when(!sel, |b| {
                                                b.bg(rgba(0xffffff0f))
                                                    .text_color(text_sec)
                                                    .hover(|h| h.bg(rgba(0xffffff1a)))
                                            })
                                            .on_click(cx.listener(move |this, _, _, cx| {
                                                this.settings.island_body_width = w;
                                                let _ = this.settings.save();
                                                cx.notify();
                                            }))
                                            .child(format!("{}px", w))
                                    })),
                            ),
                    ),
            )
            // SECTION 3: Wallpaper Filmstrip & Animation
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_3()
                    .p_4()
                    .rounded_2xl()
                    .bg(card_bg)
                    .border_1()
                    .border_color(card_border)
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::BOLD)
                            .child("Wallpaper Notch Options"),
                    )
                    // Instant Switch toggle (Real-time auto save)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(text_sec)
                                            .child("Instant Wallpaper Swap"),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(text_muted)
                                            .child("Swap instantly without diagonal reveal wipe animation"),
                                    ),
                            )
                            .child(
                                div()
                                    .id("instant-switch-toggle")
                                    .w(px(52.))
                                    .h(px(28.))
                                    .rounded_full()
                                    .p_1()
                                    .cursor_pointer()
                                    .when(instant_wp, |s| s.bg(accent))
                                    .when(!instant_wp, |s| s.bg(rgba(0xffffff20)))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.settings.wallpaper_instant_switch =
                                            !this.settings.wallpaper_instant_switch;
                                        let _ = this.settings.save();
                                        cx.notify();
                                    }))
                                    .child(
                                        div()
                                            .size(px(20.))
                                            .rounded_full()
                                            .bg(rgb(0xffffff))
                                            .when(instant_wp, |s| s.ml(px(24.)))
                                            .when(!instant_wp, |s| s.ml(px(0.))),
                                    ),
                            ),
                    )
                    // Max Thumbs (Real-time auto save)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .justify_between()
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("Visible Filmstrip Thumbnails"),
                            )
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .gap_1()
                                    .children([5, 7, 9].into_iter().map(|cnt| {
                                        let sel = thumbs_cnt == cnt;
                                        div()
                                            .id(("thumbs-cnt", cnt))
                                            .px_3()
                                            .py_1()
                                            .rounded_md()
                                            .text_xs()
                                            .font_weight(FontWeight::MEDIUM)
                                            .cursor_pointer()
                                            .when(sel, |b| b.bg(accent).text_color(rgb(0x111111)))
                                            .when(!sel, |b| {
                                                b.bg(rgba(0xffffff0f))
                                                    .text_color(text_sec)
                                                    .hover(|h| h.bg(rgba(0xffffff1a)))
                                            })
                                            .on_click(cx.listener(move |this, _, _, cx| {
                                                this.settings.wallpaper_max_visible_thumbs = cnt;
                                                let _ = this.settings.save();
                                                cx.notify();
                                            }))
                                            .child(format!("{}", cnt))
                                    })),
                            ),
                    ),
            )
            // SECTION 4: Actions & Feedback
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .justify_between()
                    .pt_2()
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .gap_3()
                            // Reset defaults
                            .child(
                                div()
                                    .id("btn-reset-defaults")
                                    .px_4()
                                    .py_2()
                                    .rounded_xl()
                                    .bg(rgba(0xffffff10))
                                    .text_color(text_sec)
                                    .text_sm()
                                    .font_weight(FontWeight::MEDIUM)
                                    .cursor_pointer()
                                    .hover(|h| h.bg(rgba(0xffffff1c)))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.settings = LumaniaSettings::default();
                                        let _ = this.settings.save();
                                        this.save_status = Some("Reset to standard defaults.".into());
                                        cx.notify();
                                    }))
                                    .child("Reset Defaults"),
                            )
                            // Restart shell
                            .child(
                                div()
                                    .id("btn-restart-shell")
                                    .px_4()
                                    .py_2()
                                    .rounded_xl()
                                    .bg(rgba(0xffffff0a))
                                    .border_1()
                                    .border_color(card_border)
                                    .text_color(text_sec)
                                    .text_sm()
                                    .font_weight(FontWeight::MEDIUM)
                                    .cursor_pointer()
                                    .hover(|h| h.bg(rgba(0xffffff14)))
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        match LumaniaSettings::restart_shell() {
                                            Ok(msg) => this.save_status = Some(msg),
                                            Err(e) => this.save_status = Some(format!("Restart error: {}", e)),
                                        }
                                        cx.notify();
                                    }))
                                    .child("Restart Shell"),
                            ),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(accent)
                            .child(self.save_status.clone().unwrap_or_default()),
                    ),
            )
    }

    fn render_mode_pill(
        &self,
        label: &'static str,
        active: bool,
        mode: &'static str,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let accent = self.theme.accent;
        let text_sec = self.theme.text_secondary;
        let id_num: usize = if mode == "accent" { 0 } else { 1 };

        div()
            .id(("mode-pill", id_num))
            .px_3()
            .py_1()
            .rounded_md()
            .text_xs()
            .font_weight(FontWeight::MEDIUM)
            .cursor_pointer()
            .when(active, |b| b.bg(accent).text_color(rgb(0x111111)))
            .when(!active, |b| {
                b.text_color(text_sec).hover(|h| h.bg(rgba(0xffffff0f)))
            })
            .on_click(cx.listener(move |this, _, _, cx| {
                this.settings.wallpaper_color_mode = mode.into();
                let _ = this.settings.save();
                cx.notify();
            }))
            .child(label)
    }

    fn render_style_pill(
        &self,
        label: &'static str,
        active: bool,
        style: &'static str,
        cx: &mut Context<Self>,
    ) -> impl IntoElement {
        let accent = self.theme.accent;
        let text_sec = self.theme.text_secondary;
        let id_num: usize = if style == "squircle" { 0 } else { 1 };

        div()
            .id(("style-pill", id_num))
            .px_3()
            .py_1()
            .rounded_md()
            .text_xs()
            .font_weight(FontWeight::MEDIUM)
            .cursor_pointer()
            .when(active, |b| b.bg(accent).text_color(rgb(0x111111)))
            .when(!active, |b| {
                b.bg(rgba(0xffffff0f))
                    .text_color(text_sec)
                    .hover(|h| h.bg(rgba(0xffffff1a)))
            })
            .on_click(cx.listener(move |this, _, _, cx| {
                this.settings.corner_style = style.into();
                let _ = this.settings.save();
                cx.notify();
            }))
            .child(label)
    }

    fn render_updates_page(&mut self, cx: &mut Context<Self>) -> Div {
        let accent = self.theme.accent;
        let card_bg = self.theme.card_bg;
        let card_border = self.theme.card_border;
        let text_sec = self.theme.text_secondary;
        let text_muted = self.theme.text_muted;
        let version = self.update_mgr.current_version.clone();
        let commit = self.update_mgr.current_commit.clone();
        let message = self.update_mgr.commit_message.clone();
        let status = self.update_mgr.status.clone();
        let logs = self.update_mgr.logs.clone();

        div()
            .flex()
            .flex_col()
            .gap_5()
            // SECTION 1: Current Status Card
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_3()
                    .p_5()
                    .rounded_2xl()
                    .bg(card_bg)
                    .border_1()
                    .border_color(card_border)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .justify_between()
                            .items_center()
                            .child(
                                div()
                                    .flex()
                                    .flex_col()
                                    .gap_1()
                                    .child(
                                        div()
                                            .flex()
                                            .flex_row()
                                            .items_center()
                                            .gap_2()
                                            .child(
                                                div()
                                                    .text_base()
                                                    .font_weight(FontWeight::BOLD)
                                                    .child(format!("Lumania Shell v{}", version)),
                                            )
                                            .child(
                                                div()
                                                    .px_2()
                                                    .py_0p5()
                                                    .rounded_md()
                                                    .bg(rgba(0x41cd5228))
                                                    .text_color(rgb(0x41cd52))
                                                    .text_xs()
                                                    .font_weight(FontWeight::MEDIUM)
                                                    .child("Installed"),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(text_muted)
                                            .child(format!("Revision {} · {}", commit, message)),
                                    ),
                            )
                            // Action buttons
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .gap_2()
                                    .child(
                                        div()
                                            .id("btn-check-updates")
                                            .px_4()
                                            .py_2()
                                            .rounded_xl()
                                            .bg(rgba(0xffffff12))
                                            .text_color(text_sec)
                                            .text_xs()
                                            .font_weight(FontWeight::SEMIBOLD)
                                            .cursor_pointer()
                                            .hover(|h| h.bg(rgba(0xffffff20)))
                                            .on_click(cx.listener(|this, _, _, cx| {
                                                this.update_mgr.check_for_updates();
                                                cx.notify();
                                            }))
                                            .child("Check for Updates"),
                                    )
                                    .when(
                                        matches!(status, UpdateStatus::UpdateAvailable(_)),
                                        |s| {
                                            s.child(
                                                div()
                                                    .id("btn-install-updates")
                                                    .px_4()
                                                    .py_2()
                                                    .rounded_xl()
                                                    .bg(accent)
                                                    .text_color(rgb(0x111111))
                                                    .text_xs()
                                                    .font_weight(FontWeight::BOLD)
                                                    .cursor_pointer()
                                                    .hover(|h| h.opacity(0.9))
                                                    .on_click(cx.listener(|this, _, _, cx| {
                                                        this.update_mgr.perform_update();
                                                        cx.notify();
                                                    }))
                                                    .child("Update Now"),
                                            )
                                        },
                                    ),
                            ),
                    )
                    // Status banner
                    .child(
                        div()
                            .p_3()
                            .rounded_xl()
                            .text_xs()
                            .font_weight(FontWeight::MEDIUM)
                            .when(status == UpdateStatus::Idle, |s| {
                                s.bg(rgba(0xffffff08)).text_color(text_muted).child(
                                    "Click 'Check for Updates' to scan origin/main & marketplace.",
                                )
                            })
                            .when(status == UpdateStatus::Checking, |s| {
                                s.bg(rgba(0xffffff10)).text_color(accent).child(
                                    "Connecting to git remote origin...",
                                )
                            })
                            .when(status == UpdateStatus::UpToDate, |s| {
                                s.bg(rgba(0x41cd5218)).text_color(rgb(0x41cd52)).child(
                                    "✓ You are running the latest version of Lumania Shell.",
                                )
                            })
                            .when(
                                matches!(status, UpdateStatus::UpdateAvailable(_)),
                                |s| {
                                    s.bg(rgba(0xe0af6825)).text_color(rgb(0xe0af68)).child(
                                        "⚡ New updates are available! Click 'Update Now' to install.",
                                    )
                                },
                            )
                            .when(status == UpdateStatus::Updating, |s| {
                                s.bg(rgba(0xffffff15)).text_color(accent).child(
                                    "Updating repository and rebuilding native helpers...",
                                )
                            })
                            .when(matches!(status, UpdateStatus::Success(_)), |s| {
                                s.bg(rgba(0x41cd5220)).text_color(rgb(0x41cd52)).child(
                                    "✓ Lumania Shell updated and reloaded successfully!",
                                )
                            })
                            .when(matches!(status, UpdateStatus::Failed(_)), |s| {
                                s.bg(rgba(0xf7768e20)).text_color(rgb(0xf7768e)).child(
                                    "Failed to check/install update. See logs below.",
                                )
                            }),
                    ),
            )
            // SECTION 2: Release Changelog
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_3()
                    .p_5()
                    .rounded_2xl()
                    .bg(card_bg)
                    .border_1()
                    .border_color(card_border)
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::BOLD)
                            .child("Release Highlights & Changelog"),
                    )
                    // Release v0.1.1
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_1p5()
                            .p_3()
                            .rounded_xl()
                            .bg(rgba(0x00000025))
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .justify_between()
                                    .items_center()
                                    .child(
                                        div()
                                            .text_xs()
                                            .font_weight(FontWeight::BOLD)
                                            .text_color(accent)
                                            .child("v0.1.1 — Live Countdown & Voice Calls"),
                                    )
                                    .child(
                                        div()
                                            .text_xs()
                                            .text_color(text_muted)
                                            .child("Latest Release"),
                                    ),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("• Native Live Countdown Timer in Dynamic Island with duration parsing (e.g. 25m, 1h, 30s)"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("• Multi-activity pagination flip: scroll wheel or tap dots to flip between timer & media controls"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("• Expanded voice call overlay: caller avatar, active audio waveform & circular end-call action"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_sec)
                                    .child("• Streamlined inline timer bar with solid crisp fill and cancel button"),
                            ),
                    )
                    // Release v0.1.0
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_1p5()
                            .p_3()
                            .rounded_xl()
                            .bg(rgba(0x00000018))
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::BOLD)
                                    .text_color(text_sec)
                                    .child("v0.1.0 — Initial Desktop Shell Release"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_muted)
                                    .child("• Screen frame border with squircle curvature and Hyprland docking margin"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_muted)
                                    .child("• Dynamic Island with MPRIS media playback, PipeWire visualizer, and notifications"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_muted)
                                    .child("• Pop-out notches for app launcher, wallpaper filmstrip, workspaces, and control center"),
                            ),
                    ),
            )
            // SECTION 3: Live Output Logs
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_2()
                    .p_4()
                    .rounded_2xl()
                    .bg(rgba(0x00000045))
                    .border_1()
                    .border_color(card_border)
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .justify_between()
                            .items_center()
                            .child(
                                div()
                                    .text_xs()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .text_color(text_muted)
                                    .child("Console Output"),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(text_muted)
                                    .child(format!("{} lines", logs.len())),
                            ),
                    )
                    .child(
                        div()
                            .id("console-logs-scroll")
                            .flex()
                            .flex_col()
                            .gap_1()
                            .h(px(90.))
                            .overflow_y_scroll()
                            .children(if logs.is_empty() {
                                vec![div()
                                    .text_xs()
                                    .text_color(text_muted)
                                    .child("Ready.")]
                            } else {
                                logs.into_iter()
                                    .map(|l| {
                                        div()
                                            .text_xs()
                                            .text_color(text_sec)
                                            .child(format!("› {}", l))
                                    })
                                    .collect()
                            }),
                    ),
            )
    }
}

fn main() {
    Application::new().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(760.), px(580.0)), cx);
        cx.open_window(
            WindowOptions {
                app_id: Some("lumania-settings".into()),
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(gpui::TitlebarOptions {
                    title: Some("Lumania Shell".into()),
                    appears_transparent: true,
                    ..Default::default()
                }),
                focus: true,
                show: true,
                is_resizable: true,
                window_min_size: Some(size(px(640.), px(480.))),
                ..Default::default()
            },
            |_, cx| cx.new(|cx| LumaniaAppView::new(cx)),
        )
        .unwrap();
        cx.activate(true);
    });
}
