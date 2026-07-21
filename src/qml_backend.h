#pragma once

#include <QtCore/QString>

bool copy_image(const QString &data_url);
bool save_image(const QString &data_url, const QString &file_url);
void register_sms2_backend();
