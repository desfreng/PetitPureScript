%{

%}

%token EOF                  "#"

// Keywords
%token CASE                 "case"
%token CLASS                "class"
%token DATA                 "data"
%token DO                   "do"
%token ELSE                 "else"
%token FALSE                "false"
%token FORALL               "forall"
%token IF                   "if"
%token IMPORT               "import"
%token IN                   "in"
%token INSTANCE             "instance"
%token LET                  "let"
%token MODULE               "module"
%token OF                   "of"
%token THEN                 "then"
%token TRUE                 "true"
%token WHERE                "where"

// Tokens with data
%token <string> LINDENT     "lindent"
%token <string> UINDENT     "Uindent"
%token <string> STR_CST     "str_cst"
%token <int> INT_CST        "int_cst"

// Expressions
%token LPAR                 "("
%token RPAR                 ")"
%token EQ_SIGN              "="

// Operators
%token EQ                   "=="
%token NOT_EQ               "/="
%token LT                   "<"
%token LE                   "<="
%token GT                   ">"
%token GE                   ">="
%token PLUS                 "+"
%token MINUS                "-"
%token MUL                  "*"
%token DIV                  "/"
%token CONCAT               "<>"
%token AND                  "&&"
%token OR                   "||"

// Typing
%token ARROW                "->"
%token EQRARROW             "=>"
%token DOUBLECOLON          "::"
%token PERIOD               "."
%token COMMA                ","

// Code blocks
%token LACC                 "{"
%token RACC                 "}"
%token SEMICOLON            ";"

%start file

%type <int option> file

%%
file:
EOF { None }