using System;

using MListc;
using mutil;

class MListClient {
    static string[] pars = {"XmlFile", "Template", "Server", "Browser"};
    static string read_inkey(bool interactive) {
        var configs = Configuration.getInstance();
        string value;
        for (int i=0; i<pars.Length; i++) {
            value = configs.Get(pars[i], "-- not set --");
            Console.WriteLine("({0}) {1} : {2}", i, pars[i], value);
        }
        string ret = String.Empty;
        if (interactive) {
            Console.WriteLine("Enter parameter number to edit (empty for END)");
            ret = Console.ReadLine();
        }
        return ret;
    } 
    static int edit_config() {
        var configs = Configuration.getInstance();
        string inkey = read_inkey(true);
        while (inkey != "") {
            int i = Convert.ToInt32(inkey);
            if (i<0 || i>= pars.Length) Console.WriteLine("Invalid parameter number");
            else {
                Console.WriteLine("Enter value for {0}:", pars[i]);
                string inval = Console.ReadLine();
                configs.Add(pars[i], inval);
            }
            inkey = read_inkey(true);
        }
        return 0;
    }
    static void Dispatch(int selection) {
        switch (selection) {
            case 0: break;
            case 1: read_inkey(false);
                break;
            case 2: edit_config();
                break;
            case 3: int rc = MListC.create_local_html();
                if (rc == 0) Console.WriteLine("Lokales HTML erzeugt.");
                else Console.WriteLine("create_local_html returned: {0}", new ReturnCode(rc).ToString());
                break;
            case 4: MListC.show_local_html();
                break;
            default: Console.WriteLine("Fehlerhafte Eingabe: "+Convert.ToString(selection));
                break;
        }
    }
    static void MainMenu() {
        int auswahl = 0;
        do {
            // show basic configuration
            string xml_file = Configuration.getInstance().Get("XmlFile", "-- not set --");
            string html_tpl = Configuration.getInstance().Get("Template", "-- not set --");

            // main loop
            Console.WriteLine("------------------------------------");
            Console.WriteLine("XmlFile: "+xml_file+" ; Template: "+html_tpl);
            Console.WriteLine();
            Console.WriteLine("(1) : Konfiguration anzeigen");
            Console.WriteLine("(2) : Konfiguration ändern");
            Console.WriteLine("(3) : Lokales HTML erzeugen");
            Console.WriteLine("(4) : Lokales HTML anzeigen");
            Console.WriteLine("(5) : Bilder auf Server laden");
            Console.WriteLine("(6) : Testmail verschicken");
            Console.WriteLine("(7) : Newsletter verschicken");
            Console.WriteLine("(0) : Programm beenden");
            string eingabe = Console.ReadLine();
            auswahl = Convert.ToInt32(eingabe);
            Dispatch(auswahl);
        } while (auswahl != 0);
    }
    static int Main(string[] args) {
        try {
            Console.WriteLine("mMail Client");
            // load configuration
            Configuration.getInstance(".mlistc");
            // set message strategy
            MessageTool.getInstance().MessageToolImpl = new ConsoleMessageTool();

            if (args.Length == 0) MainMenu();
            else {
                int selection = Convert.ToInt32(args[0]);
                Dispatch(selection);
            }
        }
        catch (System.Exception e) {
            Console.WriteLine("Ein Fehler ist aufgetreten: {0}", e.Message);
            return 1;
        }

        return 0;
    }
}
