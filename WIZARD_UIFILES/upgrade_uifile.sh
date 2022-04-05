[
    {
        "step_title": "Basic settings",
        "items": [
            {
                "type": "textfield",
                "desc": "webinterface:",
                "subitems": [
                    {
                        "key": "OPENHAB_HTTP_ADDRESS",
                        "desc": "Listen address",
                        "defaultValue": "0.0.0.0",
                        "emptyText": "0.0.0.0"
                    },
                    {
                        "key": "OPENHAB_HTTP_PORT",
                        "desc": "HTTP Port",
                        "defaultValue": "8080",
                        "emptyText": "8080",
                        "validator": {
                            "allowBlank": false,
                            "minLength": 4,
                            "maxLength": 5,
                            "regex": {
                                "expr": "/[0-9]{4,5}/i",
                                "errorText": "Error: HTTP Port must consist of 4 to 5 numbers."
                            }
                        }
                    },
                    {
                        "key": "OPENHAB_HTTPS_PORT",
                        "desc": "HTTPS Port",
                        "defaultValue": "8443",
                        "emptyText": "8443",
                        "validator": {
                            "allowBlank": false,
                            "minLength": 4,
                            "maxLength": 5,
                            "regex": {
                                "expr": "/[0-9]{4,5}/i",
                                "errorText": "Error: HTTPS Port must consist of 4 to 5 numbers."
                            }
                        }
                    }
                ]
            }
        ]
    },
    {
        "step_title": "Expert settings: Karaf framework",
        "items": [
            {
                "type": "textfield",
                "desc": "Choose your ports for openhab:",
                "subitems": [
                    {
                        "key": "ORG_APACHE_KARAF_STARTREMOTESHELL",
                        "desc": "Start remote shell",
                        "defaultValue": "true",
                        "emptyText": "true",
                        "validator": {
                            "allowBlank": false
                        }
                    },
                    {
                        "key": "ORG_APACHE_KARAF_SHELL_SSHHOST",
                        "desc": "Listen address",
                        "defaultValue": "0.0.0.0",
                        "emptyText": "0.0.0.0"
                    },
                    {
                        "key": "ORG_APACHE_KARAF_SHELL_SSHPORT",
                        "desc": "HTTP Port",
                        "defaultValue": "8101",
                        "emptyText": "8101",
                        "validator": {
                            "allowBlank": false,
                            "minLength": 4,
                            "maxLength": 5,
                            "regex": {
                                "expr": "/[0-9]{4,5}/i",
                                "errorText": "Error: HTTP Port must consist of 4 to 5 numbers."
                            }
                        }
                    }
                ]
            }
        ]
    },
    {
        "step_title": "Expert settings: Java runtime",
        "items": [
            {
                "type": "textfield",
                "desc": "Setup Java related parameters:",
                "subitems": [
                    {
                        "key": "EXTRA_JAVA_OPTS",
                        "desc": "EXTRA_JAVA_OPTS",
                        "defaultValue": "",
                        "emptyText": ""
                    }
                ]
            }
        ]
    }
]
