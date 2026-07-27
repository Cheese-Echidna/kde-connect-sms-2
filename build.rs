use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("org.kde.sms2").qml_files([
        "src/qml/Main.qml",
        "src/qml/ConversationList.qml",
        "src/qml/ConversationPage.qml",
        "src/qml/EmptyPane.qml",
        "src/qml/RoundedAvatar.qml",
    ]))
    .files(["src/controller.rs"])
    .cpp_file("src/qml_backend.cpp")
    .build();
}
