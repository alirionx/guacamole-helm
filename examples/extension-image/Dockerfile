# Extension image for guacamole.extraExtensions (source "image"): the init container runs
# /bin/sh and cp from this image and copies every *.jar below /extensions into
# GUACAMOLE_HOME/extensions. Keep only the JARs of your extension(s) in it.
FROM busybox:1.36
# The webapp runs as UID 1001: the files must be world-readable.
COPY --chmod=0644 my-guacamole-extension-1.0.0.jar /extensions/
