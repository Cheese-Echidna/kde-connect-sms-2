#include "sms2/src/controller.cxxqt.h"

#include <QtCore/QByteArray>
#include <QtCore/QFile>
#include <QtCore/QUrl>
#include <QtGui/QClipboard>
#include <QtGui/QGuiApplication>
#include <QtGui/QImage>
#include <QtQml/qqml.h>

namespace {
QByteArray image_data(const QString &source)
{
    if (source.startsWith(QStringLiteral("data:"))) {
        const QByteArray encoded = source.toUtf8();
        const qsizetype separator = encoded.indexOf(',');
        return separator < 0 ? QByteArray{} : QByteArray::fromBase64(encoded.sliced(separator + 1));
    }

    QFile file(QUrl(source).toLocalFile());
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}
}

bool copy_image(const QString &data_url)
{
    QImage image;
    if (!image.loadFromData(image_data(data_url))) {
        return false;
    }
    QGuiApplication::clipboard()->setImage(image);
    return true;
}

bool save_image(const QString &data_url, const QString &file_url)
{
    const QString path = QUrl(file_url).toLocalFile();
    const QByteArray data = image_data(data_url);
    if (path.isEmpty() || data.isEmpty()) {
        return false;
    }
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(data) == data.size();
}

void register_sms2_backend()
{
    qmlRegisterType<AppController>("org.kde.sms2.backend", 1, 0, "AppController");
}
