using System;
using mutil;

class MListClient {
    static string[] pars = {"XmlFile", "Template", "Server"};
    static string read_inkey() {
        var configs = Configuration.getInstance();
        string value;
        for (int i=0; i<pars.Length; i++) {
            value = configs.Get(pars[i], "-- not set --");
            Console.WriteLine("({0}) {1} : {2}", i, pars[i], value);
        }
        Console.WriteLine("Enter parameter number to edit (empty for END)");
        return Console.ReadLine();
    } 
    static int edit_config() {
        var configs = Configuration.getInstance();
        string inkey = read_inkey();
        while (inkey != "") {
            int i = Convert.ToInt32(inkey);
            if (i<0 || i>= pars.Length) Console.WriteLine("Invalid parameter number");
            else {
                Console.WriteLine("Enter value for {0}:", pars[i]);
                string inval = Console.ReadLine();
                configs.Add(pars[i], inval);
            }
            inkey = read_inkey();
        }
        return 0;
    }
    static int MainMenu() {
        int auswahl = 0;
        do {
            // show basic configuration
            string xml_file = Configuration.getInstance().Get("XmlFile");
            if (xml_file == null) xml_file = "";
            string html_tpl = Configuration.getInstance().Get("Template");
            if (html_tpl == null) html_tpl = "";

            // main loop
            Console.WriteLine("XmlFile: "+xml_file+" ; Template: "+html_tpl);
            Console.WriteLine();
            Console.WriteLine("(1) : Konfiguration ändern");
            Console.WriteLine("(2) : Lokales HTML erzeugen");
            Console.WriteLine("(3) : Lokales HTML anzeigen");
            Console.WriteLine("(4) : HTML auf Server laden");
            Console.WriteLine("(5) : Testmail verschicken");
            Console.WriteLine("(6) : Newsletter verschicken");
            Console.WriteLine("(0) : Programm beenden");
            string eingabe = Console.ReadLine();
            auswahl = Convert.ToInt32(eingabe);
            
            switch (auswahl) {
                case 0: break;
                case 1: edit_config();
                    break;
                default: Console.WriteLine("Unknown input: "+Convert.ToString(auswahl));
                    break;
            }
        } while (auswahl != 0);
        return 0;
    }
    static int Main() {
        Console.WriteLine("mMail Client");
        // load configuration
        Configuration.getInstance(".mlistc");
        MainMenu();

        return 0;
    }
}
