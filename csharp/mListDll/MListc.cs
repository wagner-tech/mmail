using System.IO;
using System.Text.RegularExpressions;

using mDoc;
using mutil;

namespace MListc{
public class MListC {
    static public int create_local_html() {
        Configuration Config = Configuration.getInstance();
        string XmlFile = Config.Get("XmlFile", "no.xml");
        string TemplateFile = Config.Get("Template", "no.tpl");
        if (! File.Exists(XmlFile)) {
            MessageTool.getInstance().send("XML-Datei kann nicht geöffnet werden: "+XmlFile);
            return ReturnCode.FileNotFound;
        }
        if (! File.Exists(TemplateFile)) {
            MessageTool.getInstance().send("Template-Datei kann nicht geöffnet werden: "+TemplateFile);
            return ReturnCode.FileNotFound;
        }
        Worker Worker = new Worker();
        return Worker.convert(XmlFile, TemplateFile);
    }
    static public void show_local_html() {
        Configuration config = Configuration.getInstance();
        string xml_file = config.Require("XmlFile");
        string browser = config.Get("Browser", "firefox");
        string html_file = Regex.Replace(xml_file, @"\..*$", ".html");
        string strCmdText;
        System.Diagnostics.Process.Start(browser, html_file);
    }
}

} // namespace
