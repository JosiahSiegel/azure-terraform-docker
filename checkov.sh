echo "Installing checkov and dependencies"

pip install --upgrade pip
pip install testresources
pip3 install --upgrade pip && pip3 install --upgrade setuptools
pip3 install checkov

checkov --directory ./ -o junitxml > report.xml || true
