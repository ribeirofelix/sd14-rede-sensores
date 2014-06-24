interface { name = "minhaInt",
            methods = {
               getTemperature = {
                 resulttype = "string",
                 args = {{direction = "in",
                          type = "double"},
                         {direction = "in",
                          type = "double"},
                        
                        }

               },
			 setDeltaTime = {
                 resulttype = "void",
                 args = {{direction = "in",
                          type = "double"},
                        
                        }

               },
             }
            }
