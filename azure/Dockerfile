FROM mcr.microsoft.com/powershell:lts-ubuntu-18.04

ADD https://aka.ms/arm-ttk-latest /arm-ttk/arm-ttk-latest.zip
RUN apt-get update && apt-get install zip unzip bsdmainutils
RUN unzip /arm-ttk/arm-ttk-latest.zip -d /arm-ttk
RUN mkdir -p /root/.config/powershell/
RUN echo "Import-Module /arm-ttk/arm-ttk/arm-ttk.psd1" > /root/.config/powershell/Microsoft.PowerShell_profile.ps1
#RUN pwsh -Command {Import-Module /arm-ttk/arm-ttk/arm-ttk.psd1}
#RUN echo "Test-AzTemplate -TemplatePath /template \n echo $?" > /arm-ttk/process.ps1
COPY wrapper.sh /arm-ttk/wrapper.sh
RUN chmod +x /arm-ttk/wrapper.sh
ENTRYPOINT [ "bash", "/arm-ttk/wrapper.sh", "/template"]