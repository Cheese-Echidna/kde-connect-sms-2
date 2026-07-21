mod cache;
mod contacts;
mod controller;
mod kdeconnect;
mod model;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QQuickStyle, QString, QUrl};
use cxx_qt_lib_extras::QApplication;
use std::env;

fn main() {
    cxx_qt::init_crate!(sms2);

    let mut app = QApplication::new();
    QGuiApplication::set_desktop_file_name(&QString::from("org.kde.sms2"));
    controller::ffi::register_sms2_backend();

    if env::var("QT_QUICK_CONTROLS_STYLE").is_err() {
        QQuickStyle::set_style(&QString::from("org.kde.desktop"));
    }

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/org/kde/sms2/src/qml/Main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
