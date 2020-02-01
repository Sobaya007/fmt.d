module fmt.formatter;

import std;
import dparse.ast;
import dparse.lexer;
import dparse.rollback_allocator : RollbackAllocator;

private Formatter.Option globalOption;

class Formatter {
    StringCache cache;
    RollbackAllocator rba;

    enum BraceStyle {
        allman,
        otbs
    }

    enum IndentStyle {
        tab,
        space
    }

    enum EOL {
        cr,
        lf,
        crlf
    }

    struct Option {
        BraceStyle braceStyle = BraceStyle.allman;
        IndentStyle indentStyle = IndentStyle.space;
        size_t indentSize = 4;
        EOL eol = EOL.lf;
    }

    Option option;

    this() {
        cache = StringCache(StringCache.defaultBucketCount);
    }

    string formatSourceCode(string sourceCode) {
        sourceCode = sourceCode.chomp;
        globalOption = this.option;
        auto m = parse(sourceCode);
        auto resultWithoutComment = write(m);
        auto resultWithComment = insertComment(resultWithoutComment, sourceCode);
        auto resultWithEscape = escape(resultWithComment, sourceCode);
        return resultWithEscape;
    }

    string insertComment(string resultWithoutComment, string sourceCode) {
        LexerConfig config;
        auto originalTokenList = DLexer(sourceCode, config, &cache);
        auto formattedTokenList = DLexer(resultWithoutComment, config, &cache);
    
        /*
            Validation
    
            Assue that formatted code is manipulated as below 3 actions:
                1. tok!"comment", tok!"whitespace" is removed
                2. tok!"whitespace", tok!"do", tok!"{", tok!"}" is inserted
                3. string literal is indented
         */
        auto as = DLexer(sourceCode, config, &cache);
        auto bs = DLexer(resultWithoutComment, config, &cache);
    
        while (!as.empty || !bs.empty) {
            auto a = as.front;
            auto b = bs.front;
            if (a == b) {
                as.popFront();
                bs.popFront();
            } else if (a.type == tok!"stringLiteral" && b.type == tok!"stringLiteral") {
                assert(a.text.split(eol).map!(l => l.replace(ctRegex!`^ *`, "")).array == b.text.split(eol).map!(l => l.replace(ctRegex!`^ *`, "")).array);
                as.popFront();
                bs.popFront();
            } else if (a.type.among(tok!"comment", tok!"whitespace")) {
                as.popFront();
            } else if (b.type.among(tok!"whitespace", tok!"do", tok!"{", tok!"}")) {
                bs.popFront();
            } else {
                assert(false, format!"%s %s"(str(a.type), str(b.type)));
            }
        }
    
        Token[] resultTokens;
        while (!(originalTokenList.empty && formattedTokenList.empty)) {
            if (!originalTokenList.empty && !formattedTokenList.empty) {
                auto originalToken = originalTokenList.front;
                auto formattedToken = formattedTokenList.front;
    
                if (originalToken == formattedToken
                    || (originalToken.type == tok!"whitespace" && formattedToken.type == tok!"whitespace")) {
                    resultTokens ~= formattedToken;
                    originalTokenList.popFront();
                    formattedTokenList.popFront();
                    continue;
                } else if (originalToken.type == tok!"stringLiteral" && formattedToken.type == tok!"stringLiteral") {
                    resultTokens ~= originalToken;
                    originalTokenList.popFront();
                    formattedTokenList.popFront();
                    continue;
                }
            }
            if (!originalTokenList.empty) {
                auto originalToken = originalTokenList.front;

                if (originalToken.type == tok!"comment") {
                    // when many break lines are found before the inserted comment, it is assumed to be inserted by mistake
                    if (resultTokens.empty is false && resultTokens.back.text.count(eol) > originalToken.text.count(eol)) {
                        assert(resultTokens.back.text.startsWith(eol.repeat(originalToken.text.count(eol)+1).join));
                        resultTokens.back.text = resultTokens.back.text[originalToken.text.count(eol)+1 .. $];
                    }
    
                    resultTokens ~= originalToken;
                    originalTokenList.popFront();
    
                    // when a token just after comment has eol, resulting code must be the same
                    if (originalTokenList.front.text.canFind(eol)) {
                        if (!formattedTokenList.empty && !formattedTokenList.front.text.canFind(eol) && formattedTokenList.front.type == tok!"whitespace") {
                            resultTokens ~= originalTokenList.front;
                            originalTokenList.popFront();
                            formattedTokenList.popFront();
                        } else {
                            resultTokens ~= originalTokenList.front;
                            originalTokenList.popFront();
                        }
                    }

                    continue;
                } else if (originalToken.type.among(tok!"whitespace")) {
                    originalTokenList.popFront();
                    continue;
                }
            }
            if (!formattedTokenList.empty) {
                auto formattedToken = formattedTokenList.front;
                if (formattedToken.type.among(tok!"whitespace", tok!"do", tok!"{", tok!"}")) {
                    resultTokens ~= formattedToken;
                    formattedTokenList.popFront();
                    continue;
                }
            }
            assert(false);
        }

        return resultTokens.map!write.join;
    }

    string escape(string resultWithComment, string sourceCode) {
        LexerConfig config;
        auto originalTokenList = DLexer(sourceCode, config, &cache).array;
        auto formattedTokenList = DLexer(resultWithComment, config, &cache).array;

        struct Range {
            long begin = -1, end = -1;
        }

        Range[] getRangeList(const Token[] tokenList) {
            Range[] rs;
            foreach (i, token; tokenList) {
                if (token.type != tok!"comment") continue;
                if (token.text.canFind("format off")) {
                    if (!rs.empty && rs.back.begin >= 0) continue;
                    rs ~= Range(i, -1);
                }
                if (token.text.canFind("format on")) {
                    if (rs.empty) continue;
                    rs.back.end = i;
                }
            }
            if (!rs.empty && rs.back.end == -1) {
                rs.back.end = tokenList.length;
            }
            return rs;
        }

        auto originalRangeList = getRangeList(originalTokenList);
        auto formattedRangeList = getRangeList(formattedTokenList);

        assert(originalRangeList.length == formattedRangeList.length);

        Token[] resultTokenList;
        foreach (i; 0..originalRangeList.length) {
            resultTokenList ~= formattedTokenList[(i == 0 ? 0 : formattedRangeList[i-1].end) .. formattedRangeList[i].begin];
            resultTokenList ~= originalTokenList[originalRangeList[i].begin .. originalRangeList[i].end];
        }
        resultTokenList ~= formattedTokenList[(formattedRangeList.empty ? 0 : formattedRangeList.back.end) .. $];
        return resultTokenList.map!write.join;
    }
    
    Module parse(string sourceCode) {
        import dparse.lexer : LexerConfig, StringCache, getTokensForParser;
        import dparse.parser : parseModule;
    
        LexerConfig config;
        auto tokens = getTokensForParser(sourceCode, config, &cache);
    
        return parseModule(tokens, "formatTarget.d", &rba);
    }

}

private {
    string write(const Module m) {
        CodeWithRange[] rs;
        if (m.moduleDeclaration)
            rs ~= CodeWithRange(m.moduleDeclaration);
        rs ~= m.declarations.map!CodeWithRange.array;
    
        return write(rs);
    }
    
    string write(const ModuleDeclaration d) {
        string result;
        if (d.deprecated_)
            result ~= format!"%s "(write(d.deprecated_));
        result ~= format!"module %s;"(write(d.moduleName));
        return result;
    }
    
    string write(const Deprecated d) {
        if (d.assignExpression)
            return format!"deprecated(%s)"(write(d.assignExpression));
        else
            return "deprecated";
    }
    
    string write(const IdentifierChain i) {
        return i.identifiers.map!(id => write(id)).join(".");
    }
    
    string write(const Token t) {
        assert(t.trailingComment == "");
        if (t.text) return t.text;
        if (t.type) return str(t.type);
        return "";
    }
    
    string write(const IdType i) {
        return str(i);
    }
    
    alias SimpleBinaryExpression = AliasSeq!(
        AndAndExpression,
        AndExpression,
        AsmAndExp,
        AsmLogAndExp,
        AsmLogOrExp,
        AsmOrExp,
        AsmXorExp,
        OrExpression,
        OrOrExpression,
        PowExpression,
        XorExpression,
    );
    
    alias BinaryExpressionWithOpreator = AliasSeq!(
        AsmAddExp,
        AsmMulExp,
        AsmRelExp,
        AsmShiftExp,
        AsmEqualExp,
        AddExpression,
        MulExpression,
        RelExpression,
        ShiftExpression,
        EqualExpression,
    );
    
    string write(const ExpressionNode e) {
        alias OtherExpression = AliasSeq!(
            AsmEqualExp,
            EqualExpression,
            IdentityExpression,
            InExpression,
            AsmBrExp,
            AsmExp,
            AsmUnaExp,
            AssertExpression,
            AssignExpression,
            CmpExpression,
            DeleteExpression,
            Expression,
            FunctionCallExpression,
            FunctionLiteralExpression,
            ImportExpression,
            IndexExpression,
            IsExpression,
            MixinExpression,
            NewAnonClassExpression,
            NewExpression,
            PragmaExpression,
            PrimaryExpression,
            Index,
            TemplateMixinExpression,
            TernaryExpression,
            TraitsExpression,
            TypeidExpression,
            TypeofExpression,
            UnaryExpression,
        );
    
        static foreach (E; SimpleBinaryExpression)
            if (auto ex = cast(E)e)
                return writeSimpleBinaryExpression(ex);
    
        static foreach (E; BinaryExpressionWithOpreator)
            if (auto ex = cast(E)e)
                return writeBinaryExpressionWithOperator(ex);
        static foreach (E; OtherExpression)
            if (auto ex = cast(E)e)
                return write(ex);
        assert(false);
    }
    
    string writeBinaryExpression(BE)(BE e, string op) {
        return format!"%s %s %s"(write(e.left), op, write(e.right));
    }
    
    string writeSimpleBinaryExpression(BE)(BE e) {
        string op;
        static if (is(BE == AsmAndExp)) op = "&";
        else static if (is(BE == AsmLogAndExp)) op = "&&";
        else static if (is(BE == AsmOrExp)) op = "|";
        else static if (is(BE == AsmLogOrExp)) op = "||";
        else static if (is(BE == AsmXorExp)) op = "^";
        else static if (is(BE == AndExpression)) op = "&";
        else static if (is(BE == AndAndExpression)) op = "&&";
        else static if (is(BE == OrExpression)) op = "|";
        else static if (is(BE == OrOrExpression)) op = "||";
        else static if (is(BE == PowExpression)) op = "^^";
        else static if (is(BE == XorExpression)) op = "^";
        return writeBinaryExpression(e, op);
    }
    
    string writeBinaryExpressionWithOperator(BE)(BE e) {
        return writeBinaryExpression(e, str(e.operator));
    }
    
    string write(const IdentityExpression e) {
        return writeBinaryExpression(e, e.negated ? "!is" : "is");
    }
    
    string write(const InExpression e) {
        return writeBinaryExpression(e, e.negated ? "!in" : "in");
    }
    
    string write(const AsmBrExp e) {
        if (e.asmUnaExp)
            return write(e.asmUnaExp);
        if (e.asmBrExp)
            return format!"%s[%s]"(write(e.asmBrExp), write(e.asmExp));
        else
            return format!"[%s]"(write(e.asmExp));
    }
    
    string write(const AsmExp e) {
        if (e.right)
            return format!"%s ? %s : %s"(write(e.left), write(e.middle), write(e.right));
        else
            return write(e.left);
    }
    
    string write(const AsmUnaExp e) {
        if (e.asmTypePrefix)
            return format!"%s %s"(write(e.asmTypePrefix), write(e.asmExp));
        if (e.asmPrimaryExp)
            return write(e.asmPrimaryExp);
        if (e.asmExp)
            return format!"%s%s"(write(e.prefix), write(e.asmExp));
        if (e.asmUnaExp)
            return format!"%s%s"(write(e.prefix), write(e.asmUnaExp));
        assert(false);
    }
    
    string write(const AsmTypePrefix e) {
        if (write(e.right) != "")
            return format!"%s%s"(write(e.left), write(e.right));
        else
            return format!"%s"(write(e.left));
    }
    
    string write(const AsmPrimaryExp e) {
        if (write(e.token) != "")
            return write(e.token);
        if (e.register) {
            if (e.segmentOverrideSuffix)
                return format!"%s : %s"(write(e.register), write(e.segmentOverrideSuffix));
            else
                return write(e.register);
        }
        if (e.identifierChain)
            return write(e.identifierChain);
        assert(false);
    }
    
    string write(const Register r) {
        if (r.hasIntegerLiteral)
            return format!"%s(%s)"(write(r.identifier), write(r.intLiteral));
        else
            return format!"%s"(write(r.identifier));
    }
    
    string write(const AssertExpression e) {
        return format!"assert(%s)"(write(e.assertArguments));
    }
    
    string write(const AssignExpression e) {
        return format!"%s %s %s"(write(e.ternaryExpression), str(e.operator), write(e.expression));
    }
    
    string write(const CmpExpression e) {
        if (e.shiftExpression) return write(e.shiftExpression);
        if (e.equalExpression) return write(e.equalExpression);
        if (e.identityExpression) return write(e.identityExpression);
        if (e.relExpression) return write(e.relExpression);
        if (e.inExpression) return write(e.inExpression);
        assert(false);
    }
    
    string write(const DeleteExpression e) {
        return format!"delete %s"(write(e.unaryExpression));
    }
    
    string write(const Expression e) {
        return e.items.map!(item => write(item)).join(", ");
    }
    
    string write(const FunctionCallExpression e) {
        if (e.type)
            return format!"%s%s"(write(e.type), write(e.arguments));
        if (e.unaryExpression)
            return format!"%s%s"(write(e.unaryExpression), write(e.arguments));
        if (e.templateArguments)
            return format!"%s%s"(write(e.templateArguments), write(e.arguments));
        assert(false);
    }
    
    string write(const FunctionLiteralExpression e) {
        string result;
        if (e.functionOrDelegate)
            result ~= write(e.functionOrDelegate);
        if (e.isReturnRef)
            result = [result, "ref"].join(" ");
        if (e.returnType)
            result = [result, write(e.returnType)].join(" ");
        if (e.parameters) {
            result ~= write(e.parameters);
            if (e.memberFunctionAttributes)
                result ~= format!" %s"(e.memberFunctionAttributes.map!write.join(" "));
        }
        if (e.specifiedFunctionBody) {
            if (result != "")
                result = format!"%s%s"(result, write(e.specifiedFunctionBody));
            else
                result = write(e.specifiedFunctionBody)[1..$];
        }
        if (write(e.identifier) != "")
            result ~= write(e.identifier);
        if (e.assignExpression)
            result ~= format!" => %s"(write(e.assignExpression));
        return result;
    }
    
    string write(const ImportExpression e) {
        return format!"import(%s)"(write(e.assignExpression));
    }
    
    string write(const IndexExpression e) {
         return format!"%s[%s]"(write(e.unaryExpression), e.indexes.map!write.join(",  "));
    }
    
    string write(const IsExpression e) {
        string result = write(e.type);
        if (write(e.identifier) != "")
            result ~= format!" %s"(write(e.identifier));
        if (e.typeSpecialization)
            result ~= format!" %s %s"(write(e.equalsOrColon), write(e.typeSpecialization));
        if (e.templateParameterList)
            result ~= format!", %s"(write(e.templateParameterList));
        return format!"is(%s)"(result);
    }
    
    string write(const MixinExpression e) {
        return format!"mixin(%s)"(write(e.argumentList));
    }
    
    string write(const NewAnonClassExpression e) {
        string result = "new";
         if (e.allocatorArguments)
             result ~= format!" %s"(write(e.allocatorArguments));
         result ~= " class";
         if (e.constructorArguments)
             result ~= format!" %s"(write(e.constructorArguments));
         if (e.baseClassList)
             result ~= format!" %s"(write(e.baseClassList));
         result ~= format!" %s%s"(braceBreak, write(e.structBody));
         return result;
    }
    
    string write(const NewExpression e) {
        if (e.newAnonClassExpression)
            return write(e.newAnonClassExpression);
        if (e.arguments)
            return format!"new %s%s"(write(e.type), write(e.arguments));
        if (e.assignExpression)
            return format!"new %s[%s]"(write(e.type), write(e.assignExpression));
        return format!"new %s"(write(e.type));
    }
    
    string write(const PragmaExpression e) {
        if (e.argumentList)
            return format!"pragma(%s, %s)"(write(e.identifier), write(e.argumentList));
        else
            return format!"pragma(%s)"(write(e.identifier));
    }
    
    string write(const PrimaryExpression e) {
        if (e.identifierOrTemplateInstance) {
            if (write(e.dot) != "")
                return format!"%s%s"(write(e.dot), write(e.identifierOrTemplateInstance));
            else
                return format!"%s"(write(e.identifierOrTemplateInstance));
        }
        if (write(e.typeConstructor) != "")
            return format!"%s(%s).%s"(write(e.typeConstructor), write(e.type), write(e.primary));
        if (write(e.basicType) != "") {
            if (write(e.primary) != "")
                return format!"%s.%s"(write(e.basicType), write(e.primary));
            if (e.arguments)
                return format!"%s%s"(write(e.basicType), write(e.arguments));
        }
        if (e.typeofExpression)
            return write(e.typeofExpression);
        if (e.typeidExpression)
            return write(e.typeidExpression);
        if (e.vector)
            return write(e.vector);
        if (e.arrayLiteral)
            return write(e.arrayLiteral);
        if (e.assocArrayLiteral)
            return write(e.assocArrayLiteral);
        if (e.expression)
            return format!"(%s)"(write(e.expression));
        if (e.isExpression)
            return write(e.isExpression);
        if (e.functionLiteralExpression)
            return write(e.functionLiteralExpression);
        if (e.traitsExpression)
            return write(e.traitsExpression);
        if (e.mixinExpression)
            return write(e.mixinExpression);
        if (e.importExpression)
            return write(e.importExpression);
        if (write(e.primary) != "")
            return write(e.primary);
    
        assert(false);
    }
    
    string write(const InOutContractExpression e) {
        if (e.inContractExpression)
            return write(e.inContractExpression);
        if (e.outContractExpression)
            return write(e.outContractExpression);
        assert(false);
    }
    
    string write(const InContractExpression e) {
        return format!"in (%s)"(write(e.assertArguments));
    }
    
    string write(const OutContractExpression e) {
        if (write(e.parameter) != "")
            return format!"out (%s; %s)"(write(e.parameter), write(e.assertArguments));
        else
            return format!"out (; %s)"(write(e.assertArguments));
    }
    
    string write(const AssertArguments a) {
        if (a.message)
            return format!"%s, %s"(write(a.assertion), write(a.message));
        else
            return format!"%s"(write(a.assertion));
    }
    
    string write(const Arguments a) {
        if (a.argumentList)
            return format!"(%s)"(write(a.argumentList));
        else
            return format!"()";
    }
    
    string write(const ArrayLiteral a) {
        if (a.argumentList)
            return format!"[%s]"(write(a.argumentList));
        else
            return "[]";
    }
    
    string write(const AssocArrayLiteral a) {
        if (a.keyValuePairs)
            return format!"[%s]"(write(a.keyValuePairs));
        else
            return "[]";
    }
    
    string write(const KeyValuePairs p) {
        return p.keyValuePairs.map!write.join(", ");
    }
    
    string write(const KeyValuePair p) {
        return format!"%s : %s"(write(p.key), write(p.value));
    }
    
    string write(const Index e) {
        if (e.high)
            return format!"%s .. %s"(write(e.low), write(e.high));
        else
            return format!"%s"(write(e.low));
    }
    
    string write(const TemplateMixinExpression e) {
        string result = format!"mixin %s"(write(e.mixinTemplateName));
        if (e.templateArguments)
            result ~= write(e.templateArguments);
        if (write(e.identifier) != "")
            result ~= format!" %s"(write(e.identifier));
        return result;
    }
    
    string write(const TernaryExpression e) {
        return format!"%s ? %s : %s"(write(e.orOrExpression), write(e.expression), write(e.ternaryExpression));
    }
    
    string write(const TraitsExpression e) {
        return format!"__traits(%s, %s)"(write(e.identifier), write(e.templateArgumentList));
    }
    
    string write(const TypeidExpression e) {
        if (e.type)
            return format!"typeid(%s)"(write(e.type));
        if (e.expression)
            return format!"typeid(%s)"(write(e.expression));
        assert(false);
    }
    
    string write(const TypeofExpression e) {
        if (e.expression)
            return format!"typeof(%s)"(write(e.expression));
        else
            return format!"typeof(%s)"(write(e.return_));
    }
    
    string write(const UnaryExpression e) {
        if (e.primaryExpression)
            return write(e.primaryExpression);
        if (write(e.prefix) != "")
            return format!"%s%s"(write(e.prefix), write(e.unaryExpression));
        if (e.newExpression) {
            if (e.unaryExpression)
                return format!"%s.%s"(write(e.unaryExpression), write(e.newExpression));
            else
                return write(e.newExpression);
        }
        if (e.deleteExpression)
            return write(e.deleteExpression);
        if (e.castExpression)
            return write(e.castExpression);
        if (e.assertExpression)
            return write(e.assertExpression);
        if (e.functionCallExpression)
            return write(e.functionCallExpression);
        if (e.indexExpression)
            return write(e.indexExpression);
        if (e.type)
            return format!"(%s).%s"(write(e.type), write(e.identifierOrTemplateInstance));
        if (e.identifierOrTemplateInstance)
            return format!"%s.%s"(write(e.unaryExpression), write(e.identifierOrTemplateInstance));
        if (write(e.suffix) != "")
            return format!"%s%s"(write(e.unaryExpression), write(e.suffix));
        assert(false);
    }
    
    string write(const CastExpression e) {
        if (e.type)
            return format!"cast(%s)%s"(write(e.type), write(e.unaryExpression));
        if (e.castQualifier)
            return format!"cast(%s)%s"(write(e.castQualifier), write(e.unaryExpression));
        return format!"cast()%s"(write(e.unaryExpression));
    }
    
    string write(const CastQualifier c) {
        if (write(c.second) != "")
            return format!"%s %s"(write(c.first), write(c.second));
        else
            return format!"%s"(write(c.first));
    }
    
    string write(const Type t) {
        string[] result;
        result ~= t.typeConstructors.map!write.array;
        result ~= write(t.type2);
        result = [result.join(" ")];
        result ~= t.typeSuffixes.map!write.array;
        result = result.map!(s => s.startsWith("function") ? " "~s : s).array;
        result = result.map!(s => s.startsWith("delegate") ? " "~s : s).array;
        return result.join;
    }
    
    string write(const Type2 t) {
        if (t.builtinType)
            return write(t.builtinType);
        if (t.typeIdentifierPart) {
            if (t.superOrThis)
                return format!"%s.%s"(write(t.superOrThis), write(t.typeIdentifierPart));
            else if (t.typeofExpression)
                return format!"%s.%s"(write(t.typeofExpression), write(t.typeIdentifierPart));
            else
                return format!"%s"(write(t.typeIdentifierPart));
        }
        if (t.superOrThis)
            return write(t.superOrThis);
        if (t.typeofExpression)
            return write(t.typeofExpression);
        if (t.typeConstructor)
            return format!"%s(%s)"(write(t.typeConstructor), write(t.type));
        if (t.traitsExpression)
            return write(t.traitsExpression);
        if (t.vector)
            return write(t.vector);
        if (t.mixinExpression)
            return write(t.mixinExpression);
        assert(false);
    }
    
    string write(const TypeSuffix t) {
        if (write(t.star) != "")
            return write(t.star);
        if (t.array) {
            if (t.high)
                return format!"[%s .. %s]"(write(t.low), write(t.high));
            if (t.low)
                return format!"[%s]"(write(t.low));
            if (t.type)
                return format!"[%s]"(write(t.type));
            return "[]";
        }
        if (write(t.delegateOrFunction) != "") {
            if (t.memberFunctionAttributes)
                return format!"%s%s %s"(write(t.delegateOrFunction), write(t.parameters), t.memberFunctionAttributes.map!write.join(" "));
            else
                return format!"%s%s"(write(t.delegateOrFunction), write(t.parameters));
        }
        assert(false);
    }
    
    string write(const TypeIdentifierPart t) {
        if (t.typeIdentifierPart) {
            if (t.indexer)
                return format!"%s[%s].%s"(write(t.identifierOrTemplateInstance), write(t.indexer), write(t.typeIdentifierPart));
            else
                return format!"%s.%s"(write(t.identifierOrTemplateInstance), write(t.typeIdentifierPart));
        } else {
            if (t.indexer)
                return format!"%s[%s]"(write(t.identifierOrTemplateInstance), write(t.indexer));
            else
                return format!"%s"(write(t.identifierOrTemplateInstance));
        }
    }
    
    string write(const dparse.ast.Parameters p) {
        if (p.hasVarargs)
            return format!"(%s...)"(p.parameters.map!write.join(", "));
        else
            return format!"(%s)"(p.parameters.map!write.join(", "));
    }
    
    string write(const Parameter p) {
        string result;
        if (p.parameterAttributes)
            result = format!"%s "(p.parameterAttributes.map!write.join(" "));
        result ~= write(p.type);
        if (write(p.name) != "")
            result ~= format!" %s%s"(write(p.name), p.cstyle.map!write.join);
        if (p.vararg)
            result ~= "...";
        else if (p.default_)
            result ~= format!" = %s"(write(p.default_));
        return result;
    }
    
    string write(const ParameterAttribute a) {
        if (a.atAttribute)
            return write(a.atAttribute);
        else
            return write(a.idType);
    }
    
    string write(const dparse.ast.FunctionAttribute a) {
        if (a.atAttribute)
            return write(a.atAttribute);
        return write(a.token);
    }
    
    string write(const Attribute a) {
        if (a.pragmaExpression)
            return write(a.pragmaExpression);
        if (a.alignAttribute)
            return write(a.alignAttribute);
        if (a.deprecated_)
            return write(a.deprecated_);
        if (a.atAttribute)
            return write(a.atAttribute);
        if (a.linkageAttribute)
            return write(a.linkageAttribute);
        if (a.identifierChain)
            return format!"%s(%s)"(write(a.attribute), write(a.identifierChain));
        return write(a.attribute);
    }
    
    string write(const AtAttribute a) {
        if (write(a.identifier) != "") {
            if (a.argumentList)
                return format!"@%s(%s)"(write(a.identifier), write(a.argumentList));
            else if (a.tokens.canFind!(t => t.type == tok!"("))
                return format!"@%s()"(write(a.identifier));
            else
                return format!"@%s"(write(a.identifier));
        }
        if (a.argumentList)
            return format!"@(%s)"(write(a.argumentList));
        if (a.templateInstance)
            return format!"@%s"(write(a.templateInstance));
        assert(false);
    }
    
    string write(const MemberFunctionAttribute a) {
        if (a.atAttribute)
            return write(a.atAttribute);
        else
            return write(a.tokenType);
    }
    
    string write(const AlignAttribute a) {
        if (a.assignExpression)
            return format!"align(%s)"(write(a.assignExpression));
        else
            return "align";
    }
    
    string write(const LinkageAttribute a) {
        if (a.hasPlusPlus) {
            if (a.typeIdentifierPart)
                return format!"extern(%s++, %s)"(write(a.identifier), write(a.typeIdentifierPart));
            if (a.classOrStruct)
                return format!"extern(%s++, %s)"(write(a.identifier), write(a.classOrStruct));
            else
                return format!"extern(%s++)"(write(a.identifier));
        }
        if (write(a.identifier) == "Objective")
            return format!"extern(%s-C)"(write(a.identifier));
        else
            return format!"extern(%s)"(write(a.identifier));
    }
    
    string write(const StorageClass s) {
        if (s.alignAttribute)
            return write(s.alignAttribute);
        if (s.linkageAttribute)
            return write(s.linkageAttribute);
        if (s.atAttribute)
            return write(s.atAttribute);
        if (s.deprecated_)
            return write(s.deprecated_);
        return write(s.token);
    }
    
    string write(const Vector v) {
        return format!"__vector(%s)"(write(v.type));
    }
    
    string write(string delimitor=" ")(const ArgumentList a) {
        return writeList(a, a.items, delimitor);
    }
    
    string write(const TemplateInstance t) {
        return format!"%s%s"(write(t.identifier), write(t.templateArguments));
    }
    
    string write(const TemplateArguments t) {
        if (t.templateSingleArgument)
            return format!"!%s"(write(t.templateSingleArgument));
        else if (t.templateArgumentList)
            return format!"!(%s)"(write(t.templateArgumentList));
        else
            return format!"!()";
    }
    
    string write(const TemplateSingleArgument t) {
        return write(t.token);
    }
    
    string write(const TemplateArgumentList t) {
        return t.items.map!write.join(", ");
    }
    
    string write(const TemplateArgument t) {
        if (t.assignExpression)
            return write(t.assignExpression);
        else
            return write(t.type);
    }
    
    string write(const TemplateParameters t) {
        if (t.templateParameterList)
            return format!"(%s)"(write(t.templateParameterList));
        else
            return format!"()";
    }
    
    string write(const TemplateParameterList t) {
        return t.items.map!write.join(", ");
    }
    
    string write(const TemplateParameter t) {
        if (t.templateTypeParameter)
            return write(t.templateTypeParameter);
        if (t.templateValueParameter)
            return write(t.templateValueParameter);
        if (t.templateAliasParameter)
            return write(t.templateAliasParameter);
        if (t.templateTupleParameter)
            return write(t.templateTupleParameter);
        if (t.templateThisParameter)
            return write(t.templateThisParameter);
        assert(false);
    }
    
    string write(const TemplateTypeParameter t) {
        string result = write(t.identifier);
        if (t.colonType)
            result ~= format!" : %s"(write(t.colonType));
        if (t.assignType)
            result ~= format!" = %s"(write(t.assignType));
        return result;
    }
    
    string write(const TemplateValueParameter t) {
        string result = format!"%s %s"(write(t.type), write(t.identifier));
        if (t.assignExpression)
            result ~= format!" : %s"(write(t.assignExpression));
        if (t.templateValueParameterDefault)
            result ~= format!" %s"(write(t.templateValueParameterDefault));
        return result;
    }
    
    string write(const TemplateValueParameterDefault t) {
        if (t.assignExpression)
            return format!"= %s"(write(t.assignExpression));
        else
            return format!"= %s"(write(t.token));
    }
    
    string write(const TemplateAliasParameter t) {
        string result = "alias";
        if (t.type)
            result ~= format!" %s"(write(t.type));
        result ~= format!" %s"(write(t.identifier));
        if (t.colonType)
            result ~= format!" : %s"(write(t.colonType));
        if (t.colonExpression)
            result ~= format!" : %s"(write(t.colonExpression));
        if (t.assignType)
            result ~= format!" = %s"(write(t.assignType));
        if (t.assignExpression)
            result ~= format!" = %s"(write(t.assignExpression));
        return result;
    }
    
    string write(const TemplateTupleParameter t) {
        return format!"%s..."(write(t.identifier));
    }
    
    string write(const TemplateThisParameter t) {
        return format!"this %s"(write(t.templateTypeParameter));
    }
    
    string write(const Constraint c) {
        return format!"if (%s)"(write(c.expression));
    }
    
    string write(const IdentifierOrTemplateInstance i) {
        if (i.templateInstance)
            return write(i.templateInstance);
        else
            return write(i.identifier);
    }
    
    string write(const Declaration d) {
        string[] result = d.attributes.map!write.array;
    
        if (d.declarations) {
            string[] lines;
            lines ~= result.join(" ");
            lines ~= "{";
            lines ~= d.declarations.map!CodeWithRange.array.write.insertIndent;
            lines ~= "}";
            return lines.join(eol);
        }
    
        if (d.aliasDeclaration) result ~= write(d.aliasDeclaration);
        if (d.aliasThisDeclaration) result ~= write(d.aliasThisDeclaration);
        if (d.anonymousEnumDeclaration) result ~= write(d.anonymousEnumDeclaration);
        if (d.attributeDeclaration) result ~= write(d.attributeDeclaration);
        if (d.classDeclaration) result ~= write(d.classDeclaration);
        if (d.conditionalDeclaration) result ~= write(d.conditionalDeclaration);
        if (d.constructor) result ~= write(d.constructor);
        if (d.debugSpecification) result ~= write(d.debugSpecification);
        if (d.destructor) result ~= write(d.destructor);
        if (d.enumDeclaration) result ~= write(d.enumDeclaration);
        if (d.eponymousTemplateDeclaration) result ~= write(d.eponymousTemplateDeclaration);
        if (d.functionDeclaration) result ~= write(d.functionDeclaration);
        if (d.importDeclaration) result ~= write(d.importDeclaration);
        if (d.interfaceDeclaration) result ~= write(d.interfaceDeclaration);
        if (d.invariant_) result ~= write(d.invariant_);
        if (d.mixinDeclaration) result ~= write(d.mixinDeclaration);
        if (d.mixinTemplateDeclaration) result ~= write(d.mixinTemplateDeclaration);
        if (d.postblit) result ~= write(d.postblit);
        if (d.pragmaDeclaration) result ~= write(d.pragmaDeclaration);
        if (d.sharedStaticConstructor) result ~= write(d.sharedStaticConstructor);
        if (d.sharedStaticDestructor) result ~= write(d.sharedStaticDestructor);
        if (d.staticAssertDeclaration) result ~= write(d.staticAssertDeclaration);
        if (d.staticConstructor) result ~= write(d.staticConstructor);
        if (d.staticDestructor) result ~= write(d.staticDestructor);
        if (d.structDeclaration) result ~= write(d.structDeclaration);
        if (d.templateDeclaration) result ~= write(d.templateDeclaration);
        if (d.unionDeclaration) result ~= write(d.unionDeclaration);
        if (d.unittest_) result ~= write(d.unittest_);
        if (d.variableDeclaration) result ~= write(d.variableDeclaration);
        if (d.versionSpecification) result ~= write(d.versionSpecification);
        if (d.staticForeachDeclaration) result ~= write(d.staticForeachDeclaration);
    
        return result.join(" ");
    }
    
    string write(const AliasDeclaration d) {
        if (d.initializers)
            return format!"alias %s;"(d.initializers.map!write.join(", "));
        string result = "alias";
        if (d.storageClasses)
            result ~= format!" %s"(d.storageClasses.map!write.join(" "));
        result ~= format!" %s"(write(d.declaratorIdentifierList));
        if (d.parameters)
            result ~= format!"(%s)"(write(d.parameters));
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        result ~= ";";
        return result;
    }
    
    string write(const AliasThisDeclaration d) {
        return format!"alias %s this;"(write(d.identifier));
    }
    
    string write(const AnonymousEnumDeclaration d) {
        string result = "enum";
        if (d.baseType)
            result ~= format!" : %s"(write(d.baseType));
        result ~= writeBlock(d.members);
        return result;
    }
    
    string write(const AttributeDeclaration d) {
        return format!"%s:"(write(d.attribute));
    }
    
    string write(const ClassDeclaration d) {
        // TODO: can exchange order of constraint and base class list
        string result = format!"class %s"(write(d.name));
        if (d.templateParameters)
            result ~= write(d.templateParameters);
        if (d.baseClassList)
            result ~= format!" : %s"(write(d.baseClassList));
        if (d.constraint)
            result ~= format!"%s%s"(eol, write(d.constraint));
        if (d.structBody)
            result ~= format!"%s%s"(braceBreak, write(d.structBody));
        else
            result ~= ";";
        return result;
    }
    
    string write(const ConditionalDeclaration d) {
        string result = format!"%s%s"(write(d.compileCondition), writeBlock(d.trueDeclarations));
        if (d.hasElse) {
            if (d.falseDeclarations.length == 1 && d.falseDeclarations.front.conditionalDeclaration) {
                result ~= format!"%selse %s"(braceBreak, d.falseDeclarations.map!write.join(eol));
            } else {
                result ~= format!"%selse%s"(braceBreak, writeBlock(d.falseDeclarations));
            }
        }
        return result;
    }
    
    string write(const Constructor c) {
        string result = "this";
        if (c.templateParameters)
            result ~= write(c.templateParameters);
        result ~= write(c.parameters);
        if (c.memberFunctionAttributes)
            result ~= format!" %s"(c.memberFunctionAttributes.map!write.join(" "));
        if (c.constraint)
            result ~= format!"%s%s"(eol, write(c.constraint));
        if (c.functionBody)
            result ~= write(c.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const DebugSpecification d) {
        return format!"debug = %s;"(write(d.identifierOrInteger));
    }
    
    string write(const Destructor d) {
        auto result = "~this()";
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        if (d.functionBody)
            result ~= write(d.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const EnumDeclaration d) {
        string result = format!"enum %s"(write(d.name));
        if (d.type)
            result ~= format!" : %s"(write(d.type));
        if (d.enumBody)
            result ~= format!"%s%s"(braceBreak, write(d.enumBody));
        else
            result ~= ";";
        return result;
    }
    
    string write(const EponymousTemplateDeclaration d) {
        if (d.assignExpression)
            return format!"enum %s%s = %s;"(write(d.name), write(d.templateParameters), write(d.assignExpression));
        if (d.type)
            return format!"enum %s%s = %s;"(write(d.name), write(d.templateParameters), write(d.type));
        assert(false);
    }
    
    string write(const FunctionDeclaration d) {
        string result;
        if (d.storageClasses)
            result ~= d.storageClasses.map!write.join(" ");
        else
            result ~= write(d.returnType);
        result ~= format!" %s"(write(d.name));
        if (d.templateParameters)
            result ~= write(d.templateParameters);
        result ~= write(d.parameters);
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        if (d.attributes)
            result ~= format!" %s"(d.attributes.map!write.join(" "));
        if (d.constraint)
            result ~= format!"%s%s"(eol, write(d.constraint));
        result ~= write(d.functionBody);
        return result;
    }
    
    string write(const ImportDeclaration d) {
        if (d.singleImports) {
            if (d.importBindings)
                return format!"import %s, %s;"(d.singleImports.map!write.join(", "), write(d.importBindings));
            else
                return format!"import %s;"(d.singleImports.map!write.join(" "));
        }
        return format!"import %s;"(write(d.importBindings));
    }
    
    string write(const InterfaceDeclaration d) {
        // TODO: can exchange order of constraint and base class list
        string result = format!"interface %s"(write(d.name));
        if (d.templateParameters)
            result ~= write(d.templateParameters);
        if (d.baseClassList)
            result ~= format!" : %s"(write(d.baseClassList));
        if (d.constraint)
            result ~= format!"%s%s"(eol, write(d.constraint));
        if (d.structBody)
            result ~= format!"%s%s"(braceBreak, write(d.structBody));
        else
            result ~= ";";
        return result;
    }
    
    string write(const Invariant i) {
        if (i.blockStatement)
            return format!"invariant%s%s"(braceBreak, write(i.blockStatement));
        if (i.assertArguments)
            return format!"invariant (%s);"(write(i.assertArguments));
        assert(false);
    }
    
    string write(const MixinDeclaration d) {
        if (d.mixinExpression)
            return format!"%s;"(write(d.mixinExpression));
        if (d.templateMixinExpression)
            return format!"%s;"(write(d.templateMixinExpression));
        assert(false);
    }
    
    string write(const MixinTemplateDeclaration d) {
         return format!"mixin %s"(write(d.templateDeclaration));
    }
    
    string write(const Postblit p) {
        string result = "this(this)";
        if (p.memberFunctionAttributes)
            result ~= format!" %s"(p.memberFunctionAttributes.map!write.join(" "));
        if (p.functionBody)
            result ~= write(p.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const PragmaDeclaration d) {
        return format!"%s;"(write(d.pragmaExpression));
    }
    
    string write(const SharedStaticConstructor d) {
        string result = "shared static this()";
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        if (d.functionBody)
            result ~= write(d.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const SharedStaticDestructor d) {
        string result = "shared static ~this()";
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        if (d.functionBody)
            result ~= write(d.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const StaticAssertDeclaration d) {
        return write(d.staticAssertStatement);
    }
    
    string write(const StaticConstructor d) {
        string result = "static this()";
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        if (d.functionBody)
            result ~= write(d.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const StaticDestructor d) {
        string result = "static ~this()";
        if (d.memberFunctionAttributes)
            result ~= format!" %s"(d.memberFunctionAttributes.map!write.join(" "));
        if (d.functionBody)
            result ~= write(d.functionBody);
        else
            result ~= ";";
        return result;
    }
    
    string write(const StructDeclaration d) {
        string result = "struct";
        if (write(d.name) != "")
            result ~= format!" %s"(write(d.name));
        if (d.templateParameters)
            result ~= write(d.templateParameters);
        if (d.constraint)
            result ~= format!" %s"(write(d.constraint));
        if (d.structBody)
            result ~= format!"%s%s"(braceBreak, write(d.structBody));
        else
            result ~= ";";
        return result;
    }
    
    string write(const TemplateDeclaration d) {
        string result = format!"template %s%s"(write(d.name), write(d.templateParameters));
        if (d.constraint)
            result ~= format!" %s"(write(d.constraint));
        result ~= writeBlock(d.declarations);
        return result;
    }
    
    string write(const UnionDeclaration d) {
        string result = "union";
        if (write(d.name) != "")
            result ~= format!" %s"(write(d.name));
        if (d.templateParameters)
            result ~= write(d.templateParameters);
        if (d.constraint)
            result ~= format!"%s%s"(eol, write(d.constraint));
        if (d.structBody)
            result ~= format!"%s%s"(braceBreak, write(d.structBody));
        else
            result ~= ";";
        return result;
    }
    
    string write(const Unittest u) {
        return format!"unittest%s%s"(braceBreak, write(u.blockStatement));
    }
    
    string write(const VariableDeclaration d) {
        if (d.autoDeclaration)
            return write(d.autoDeclaration);
        return format!"%s %s;"((d.storageClasses.map!write.array ~ write(d.type)).join(" "), d.declarators.map!write.join(", "));
    }
    
    string write(const AutoDeclaration d) {
        return format!"%s %s;"(d.storageClasses.map!write.join(" "), d.parts.map!write.join(", "));
    }
    
    string write(const AutoDeclarationPart d) {
        string result = write(d.identifier);
        if (d.templateParameters)
             result ~= write(d.templateParameters);
        result ~= format!" = %s"(write(d.initializer));
        return result;
    }
    
    string write(const Declarator d) {
        string result = format!"%s%s"(write(d.name), d.cstyle.map!write.join);
        if (d.templateParameters)
            result ~= write(d.templateParameters);
        if (d.initializer)
            result ~= format!" = %s"(write(d.initializer));
        return result;
    }
    
    string write(const Initializer i) {
        if (i.nonVoidInitializer)
            return write(i.nonVoidInitializer);
        else
            return "void";
    }
    
    string write(const NonVoidInitializer i) {
        if (i.assignExpression)
            return write(i.assignExpression);
        if (i.arrayInitializer)
            return write(i.arrayInitializer);
        if (i.structInitializer)
            return write(i.structInitializer);
        assert(false);
    }
    
    string write(const ArrayInitializer i) {
        return format!"[%s]"(writeList(i, i.arrayMemberInitializations).insertIndent);
    }
    
    string write(const ArrayMemberInitialization i) {
        if (i.assignExpression)
            return format!"%s : %s"(write(i.assignExpression), write(i.nonVoidInitializer));
        else
            return format!"%s"(write(i.nonVoidInitializer));
    }
    
    string write(const StructInitializer i) {
        return format!"{%s}"(write(i.structMemberInitializers).insertIndent);
    }
    
    string write(const StructMemberInitializers i) {
        return writeList(i, i.structMemberInitializers);
    }
    
    string write(const StructMemberInitializer i) {
        if (write(i.identifier) != "")
            return format!"%s : %s"(write(i.identifier), write(i.nonVoidInitializer));
        else
            return format!"%s"(write(i.nonVoidInitializer));
    }
    
    string write(const VersionSpecification v) {
        return format!"version = %s;"(write(v.token));
    }
    
    string write(const StaticForeachDeclaration d) {
        // TODO: can select whether to use paren
        if (d.foreachTypeList)
            return format!"static %s(%s; %s)%s"(write(d.type), write(d.foreachTypeList), write(d.low), writeBlock(d.declarations));
        if (d.foreachType)
            return format!"static %s(%s; %s .. %s)%s"(write(d.type), write(d.foreachType), write(d.low), write(d.high), writeBlock(d.declarations));
        assert(false);
    }
    
    string write(const FunctionBody f) {
        if (f.specifiedFunctionBody)
            return write(f.specifiedFunctionBody);
        if (f.missingFunctionBody)
            return write(f.missingFunctionBody);
        assert(false);
    }
    
    string write(const SpecifiedFunctionBody f) {
        string result;
        if (f.functionContracts) {
            result ~= format!"%s%s%sdo"(eol, f.functionContracts.map!write.join(eol), eol);
        }
        result ~= braceBreak;
        result ~= write(f.blockStatement);
        return result;
    }
    
    string write(const MissingFunctionBody f) {
        return format!"%s;"(f.functionContracts.map!write.join(" "));
    }
    
    string write(const FunctionContract f) {
        if (f.inOutContractExpression)
            return write(f.inOutContractExpression);
        if (f.inOutStatement)
            return write(f.inOutStatement);
        assert(false);
    }
    
    string write(const DeclarationsAndStatements s) {
        return s.declarationsAndStatements.map!CodeWithRange.array.write;
    }
    
    string write(const DeclarationOrStatement s) {
        if (s.declaration)
            return write(s.declaration);
        if (s.statement)
            return write(s.statement);
        assert(false);
    }
    
    string write(const Statement s) {
        if (s.statementNoCaseNoDefault)
            return write(s.statementNoCaseNoDefault);
        if (s.caseStatement)
            return write(s.caseStatement);
        if (s.caseRangeStatement)
            return write(s.caseRangeStatement);
        if (s.defaultStatement)
            return write(s.defaultStatement);
        assert(false);
    }
    
    string write(const StatementNoCaseNoDefault s) {
        if (s.labeledStatement) return write(s.labeledStatement);
        if (s.blockStatement) return write(s.blockStatement);
        if (s.ifStatement) return write(s.ifStatement);
        if (s.whileStatement) return write(s.whileStatement);
        if (s.doStatement) return write(s.doStatement);
        if (s.forStatement) return write(s.forStatement);
        if (s.foreachStatement) return write(s.foreachStatement);
        if (s.staticForeachStatement) return write(s.staticForeachStatement);
        if (s.switchStatement) return write(s.switchStatement);
        if (s.finalSwitchStatement) return write(s.finalSwitchStatement);
        if (s.continueStatement) return write(s.continueStatement);
        if (s.breakStatement) return write(s.breakStatement);
        if (s.returnStatement) return write(s.returnStatement);
        if (s.gotoStatement) return write(s.gotoStatement);
        if (s.withStatement) return write(s.withStatement);
        if (s.synchronizedStatement) return write(s.synchronizedStatement);
        if (s.tryStatement) return write(s.tryStatement);
        if (s.throwStatement) return write(s.throwStatement);
        if (s.scopeGuardStatement) return write(s.scopeGuardStatement);
        if (s.asmStatement) return write(s.asmStatement);
        if (s.pragmaStatement) return write(s.pragmaStatement);
        if (s.conditionalStatement) return write(s.conditionalStatement);
        if (s.staticAssertStatement) return write(s.staticAssertStatement);
        if (s.versionSpecification) return write(s.versionSpecification);
        if (s.debugSpecification) return write(s.debugSpecification);
        if (s.expressionStatement) return write(s.expressionStatement);
        assert(false);
    }
    
    string write(const InOutStatement s) {
        if (s.inStatement)
            return write(s.inStatement);
        if (s.outStatement)
            return write(s.outStatement);
        assert(false);
    }
    
    string write(const InStatement s) {
        return format!"in%s%s"(braceBreak, write(s.blockStatement));
    }
    
    string write(const OutStatement s) {
        if (write(s.parameter) != "")
            return format!"out (%s)%s%s"(write(s.parameter), braceBreak, write(s.blockStatement));
        else
            return format!"out%s%s"(braceBreak, write(s.blockStatement));
    }
    
    string write(const BlockStatement s) {
        if (s.declarationsAndStatements)
            return format!"{%s%s%s}"(eol, write(s.declarationsAndStatements).insertIndent, eol);
        else
            return "{}";
    }
    
    string write(const CaseStatement s) {
        // s.declarationsAndStatements can contain default statement and it causes too much indent
        auto f = write(s.declarationsAndStatements).insertIndent.split(eol);
        auto c = f.countUntil!(l => l.match(ctRegex!` *default`).empty is false);
        if (c >= 0) {
            // assume all lines after default belong to default case
            f[c..$] = f[c..$].map!removeIndent.array;
        }
        return format!"case %s:%s%s"(write(s.argumentList), eol, f.join(eol));
    }
    
    string write(const CaseRangeStatement s) {
        return format!"case %s: ... case %s:%s%s"(write(s.low), write(s.high), eol, write(s.declarationsAndStatements).insertIndent);
    }
    
    string write(const DefaultStatement s) {
        return format!"default:%s%s"(eol, write(s.declarationsAndStatements).insertIndent);
    }
    
    string write(const LabeledStatement s) {
        // TODO: label should be always 0 level indented
        string result = format!"%s:"(s.identifier);
        if (s.declarationOrStatement)
            result ~= format!" %s"(write(s.declarationOrStatement));
        return result;
    }
    
    string write(const IfStatement s) {
        string condition;
        if (s.type) {
            if (s.typeCtors)
                condition = format!" %s"(s.typeCtors.map!write.join(" "));
            condition ~= format!"%s %s = %s"(write(s.type), write(s.identifier), write(s.expression));
        } else if (s.typeCtors) {
            condition = format!"%s %s = %s"(s.typeCtors.map!write.join(" "), write(s.identifier), write(s.expression));
        } else if (write(s.identifier) != "") {
            condition = format!"auto %s = %s"(write(s.identifier), write(s.expression));
        } else {
            condition = write(s.expression);
        }
        string result = format!"if (%s)%s"(condition, writeNest(s.thenStatement));
        if (s.elseStatement)
            result ~= format!"%selse%s"(braceBreak, writeNest(s.elseStatement));
        return result;
    }
    
    string write(const WhileStatement s) {
        return format!"while (%s)%s"(write(s.expression), writeNest(s.declarationOrStatement));
    }
    
    string write(const DoStatement s) {
        return format!"do%s%swhile (%s);"(writeNest(s.statementNoCaseNoDefault), braceBreak, write(s.expression));
    }
    
    string write(const ForStatement s) {
        return format!"for (%s %s; %s)%s"(write(s.initialization), write(s.test), write(s.increment), writeNest(s.declarationOrStatement));
    }
    
    string write(const ForeachStatement s) {
        if (s.foreachTypeList)
            return format!"%s (%s; %s)%s"(write(s.type), write(s.foreachTypeList), write(s.low), writeNest(s.declarationOrStatement));
        if (s.foreachType)
            return format!"%s (%s; %s .. %s)%s"(write(s.type), write(s.foreachType), write(s.low), write(s.high), writeNest(s.declarationOrStatement));
        assert(false);
    }
    
    string write(const StaticForeachStatement s) {
        return format!"static %s"(write(s.foreachStatement));
    }
    
    string write(const SwitchStatement s) {
        return format!"switch (%s)%s%s"(write(s.expression), braceBreak, write(s.statement));
    }
    
    string write(const FinalSwitchStatement s) {
        return format!"final %s"(write(s.switchStatement));
    }
    
    string write(const ContinueStatement s) {
         if (write(s.label) != "")
             return format!"continue %s;"(write(s.label));
         else
             return format!"continue;";
    }
    
    string write(const BreakStatement s) {
         if (write(s.label) != "")
             return format!"break %s;"(write(s.label));
         else
             return format!"break;";
    }
    
    string write(const ReturnStatement s) {
         if (s.expression)
             return format!"return %s;"(write(s.expression));
         else
             return format!"return;";
    }
    
    string write(const GotoStatement s) {
         if (write(s.label) != "")
            return format!"goto %s;"(write(s.label));
        if (s.expression)
            return format!"goto case %s;"(write(s.expression));
        assert(false);
    }
    
    string write(const WithStatement s) {
        return format!"with (%s)%s"(write(s.expression), writeNest(s.declarationOrStatement));
    }
    
    string write(const SynchronizedStatement s) {
        if (s.expression)
            return format!"synchronized (%s)%s"(write(s.expression), writeNest(s.statementNoCaseNoDefault));
        else
            return format!"synchronized%s"(writeNest(s.statementNoCaseNoDefault));
    }
    
    string write(const TryStatement s) {
        auto result = format!"try%s"(writeNest(s.declarationOrStatement));
        if (s.catches)
            result ~= format!"%s%s"(braceBreak, write(s.catches));
        if (s.finally_)
            result ~= format!"%s%s"(braceBreak, write(s.finally_));
        return result;
    }
    
    string write(const ThrowStatement s) {
         return format!"throw %s;"(write(s.expression));
    }
    
    string write(const ScopeGuardStatement s) {
        return format!"scope (%s)%s"(write(s.identifier), writeNest(s.statementNoCaseNoDefault));
    }
    
    string write(const AsmStatement s) {
        auto result = "asm";
        if (s.functionAttributes)
            result ~= format!" %s"(s.functionAttributes.map!write.join(" "));
        result ~= writeBlock(s.asmInstructions);
        return result;
    }
    
    string write(const PragmaStatement s) {
        if (s.statement)
            return format!"%s %s"(write(s.pragmaExpression), write(s.statement));
        if (s.blockStatement)
            return format!"%s%s%s"(write(s.pragmaExpression), braceBreak, write(s.blockStatement));
        return format!"%s;"(write(s.pragmaExpression));
    }
    
    string write(const ConditionalStatement s) {
        string result = format!"%s%s"(write(s.compileCondition), writeNest(s.trueStatement));
        if (s.falseStatement) {
            if (s.falseStatement.statement && s.falseStatement.statement.statementNoCaseNoDefault.conditionalStatement)
                result ~= format!"%selse %s"(braceBreak, write(s.falseStatement));
            else
                result ~= format!"%selse%s"(braceBreak, writeNest(s.falseStatement));
        }
        return result;
    }
    
    string write(const StaticAssertStatement s) {
        return format!"static %s;"(write(s.assertExpression));
    }
    
    string write(const ExpressionStatement s) {
        return format!"%s;"(write(s.expression));
    }
    
    string write(const SingleImport i) {
        if (write(i.rename) != "")
            return format!"%s = %s"(write(i.rename), write(i.identifierChain));
        else
            return format!"%s"(write(i.identifierChain));
    }
    
    string write(const ImportBindings i) {
        if (i.importBinds)
            return format!"%s : %s"(write(i.singleImport), i.importBinds.map!write.join(", "));
        else
            return format!"%s"(write(i.singleImport));
    }
    
    string write(const ImportBind i) {
        if (write(i.right) != "")
            return format!"%s = %s"(write(i.left), write(i.right));
        else
            return format!"%s"(write(i.left));
    }
    
    string write(const AliasInitializer a) {
        string result = write(a.name);
        if (a.templateParameters)
            result ~= write(a.templateParameters);
        result ~= " = ";
        if (a.functionLiteralExpression) {
            result ~= write(a.functionLiteralExpression);
        } else {
            if (a.storageClasses)
                result ~= a.storageClasses.map!write.join(" ");
            result ~= write(a.type);
            if (a.parameters) {
                result ~= write(a.parameters);
                if (a.memberFunctionAttributes)
                    result ~= format!" %s"(a.memberFunctionAttributes.map!write.join(" "));
            }
        }
        return result;
    }
    
    string write(const DeclaratorIdentifierList i) {
        return i.identifiers.map!write.join(", ");
    }
    
    string write(const TypeSpecialization t) {
        if (t.type)
            return write(t.type);
        else
            return write(t.token);
    }
    
    string write(const BaseClassList b) {
        return b.items.map!write.join(", ");
    }
    
    string write(const BaseClass b) {
        return write(b.type2);
    }
    
    string write(const StructBody s) {
        return format!"{%s%s%s}"(eol, s.declarations.map!CodeWithRange.array.write.insertIndent, eol);
    }
    
    string write(const MixinTemplateName n) {
        if (n.symbol)
            return write(n.symbol);
        else
            return format!"%s.%s"(write(n.typeofExpression), write(n.identifierOrTemplateChain));
    }
    
    string write(const Symbol s) {
        if (s.dot)
            return format!".%s"(write(s.identifierOrTemplateChain));
        else
            return format!"%s"(write(s.identifierOrTemplateChain));
    }
    
    string write(const IdentifierOrTemplateChain i) {
        return i.identifiersOrTemplateInstances.map!write.join(".");
    }
    
    string write(const AnonymousEnumMember e) {
        string result;
        if (e.type)
            result ~= format!"%s "(write(e.type));
        result ~= write(e.name);
        if (e.assignExpression)
            result ~= format!" = %s"(write(e.assignExpression));
        return result;
    }
    
    string write(const EnumBody e) {
        return format!"{%s}"(writeList(e, e.enumMembers).insertIndent);
    }
    
    string write(const EnumMember e) {
        string result;
        if (e.enumMemberAttributes)
            result = format!"%s "(e.enumMemberAttributes.map!write.join(" "));
        result ~= write(e.name);
        if (e.assignExpression)
            result ~= format!" = %s"(write(e.assignExpression));
        return result;
    }
    
    string write(const EnumMemberAttribute e) {
        if (e.atAttribute)
            return write(e.atAttribute);
        if (e.deprecated_)
            return write(e.deprecated_);
        assert(false);
    }
    
    string write(const ForeachTypeList f) {
         return f.items.map!write.join(", ");
    }
    
    string write(const dparse.ast.ForeachType f) {
        string[] result;
        if (f.isRef)
            result ~= "ref";
        if (f.isAlias)
            result ~= "alias";
        if (f.isEnum)
            result ~= "enum";
        result ~= f.typeConstructors.map!write.array;
        if (f.type)
            result ~= write(f.type);
        result ~= write(f.identifier);
        return result.join(" ");
    }
    
    string write(const Catches c) {
        string[] result = c.catches.map!write.array;
        if (c.lastCatch)
            result ~= write(c.lastCatch);
        return result.join(braceBreak);
    }
    
    string write(const Catch c) {
        if (write(c.identifier) != "")
            return format!"catch (%s %s)%s"(write(c.type), write(c.identifier), writeNest(c.declarationOrStatement));
        else
            return format!"catch (%s)%s"(write(c.type), writeNest(c.declarationOrStatement));
    }
    
    string write(const LastCatch c) {
        return format!"catch%s"(writeNest(c.statementNoCaseNoDefault));
    }
    
    string write(const Finally f) {
        return format!"finally%s"(writeNest(f.declarationOrStatement));
    }
    
    string write(const AsmInstruction i) {
        if (i.hasAlign)
            return format!"align %s"(write(i.identifierOrIntegerOrOpcode));
        if (i.operands)
            return format!"%s %s"(write(i.identifierOrIntegerOrOpcode), write(i.operands));
        if (i.asmInstruction)
            return format!"%s : %s"(write(i.identifierOrIntegerOrOpcode), write(i.asmInstruction));
        if (write(i.identifierOrIntegerOrOpcode) != "")
            return format!"%s"(write(i.identifierOrIntegerOrOpcode));
        return ";";
    }
    
    string write(const Operands o) {
         return o.operands.map!write.join(", ");
    }
    
    string write(const CompileCondition c) {
         if (c.versionCondition)
             return write(c.versionCondition);
         if (c.debugCondition)
             return write(c.debugCondition);
         if (c.staticIfCondition)
             return write(c.staticIfCondition);
         assert(false);
    }
    
    string write(const VersionCondition c) {
        return format!"version (%s)"(write(c.token));
    }
    
    string write(const DebugCondition c) {
        if (write(c.identifierOrInteger) != "")
            return format!"debug (%s)"(write(c.identifierOrInteger));
        else
            return format!"debug";
    }
    
    string write(const StaticIfCondition c) {
        return format!"static if (%s)"(write(c.assignExpression));
    }

    string writeNest(const StatementNoCaseNoDefault s) {
        if (s.blockStatement) return format!"%s%s"(braceBreak, write(s));
        else return format!"%s%s"(eol, write(s).insertIndent);
    }

    string writeNest(const DeclarationOrStatement d) {
        if (d.statement && d.statement.statementNoCaseNoDefault)
            return writeNest(d.statement.statementNoCaseNoDefault);
        else
            return write(d);
    }

    string writeList(Parent, Child)(Parent p, Child[] cs, string delimitor=eol) {
        auto c = cs.length - (p.tokens.count!(t => t.type == tok!",") - cs.map!(m => m.tokens.count!(t => t.type == tok!",")).sum);
        assert(c == 0 || c == 1);

        string pad = delimitor == eol ? delimitor : "";
        if (c == 0)
            return format!"%s%s,%s"(pad, cs.map!write.join(","~delimitor), pad);
        else
            return format!"%s%s%s"(pad, cs.map!write.join(","~delimitor), pad);
    }

    string writeBlock(Node)(Node[] nodes) {
        return format!"%s{%s%s%s}"(braceBreak, eol, nodes.map!write.join(eol).insertIndent, eol);
    }
    
    struct CodeWithRange {
        string code;
        size_t begin, end;
        invariant (begin <= end);
    
        this(Node)(const Node b) {
            this.code = write(b);
            this.begin = b.tokens.map!(t => t.line).minElement;
            this.end = b.tokens.map!(t => t.line).maxElement;
        }
    }
    
    size_t requiredLineBreaks(CodeWithRange first, CodeWithRange second) 
        in (first.end <= second.begin)
    {
        return max(1, second.begin - first.end);
    }
    
    string write(CodeWithRange[] rs) {
        string[] result = rs.map!(r => r.code).array;
        foreach (i; 1..result.length) {
            result[i-1] ~= eol.repeat(requiredLineBreaks(rs[i-1], rs[i])).join;
        }
        return result.join;
    }
    
    string indent() {
        final switch (globalOption.indentStyle) {
            case Formatter.IndentStyle.space:
                return " ".repeat(globalOption.indentSize).join;
            case Formatter.IndentStyle.tab:
                return "\t";
        }
    }
    
    string insertIndent(string s) {
        return s.split(eol).map!(l => l == "" ? l : indent ~ l).join(eol);
    }
    
    string removeIndent(string s) 
        in (s.startsWith(indent))
    {
        return s[indent.length..$];
    }

    string braceBreak() {
        final switch (globalOption.braceStyle) {
            case Formatter.BraceStyle.allman: return eol;
            case Formatter.BraceStyle.otbs: return " ";
        }
    }

    string eol() {
        final switch (globalOption.eol) {
            case Formatter.EOL.cr:
                return "\r";
            case Formatter.EOL.lf:
                return "\n";
            case Formatter.EOL.crlf:
                return "\r\n";
        }
    }
}

unittest {
    auto formatter = new Formatter;
    foreach (e; dirEntries("test", SpanMode.depth)) {
        if (e.to!string.match(ctRegex!`case(\d+)\.d`)) {
            auto a = formatter.formatSourceCode(readText(e).chomp);
            auto b = readText(e.stripExtension ~ "_ans.d").chomp;
            assert(a == b, format!"%s:\n-----\n%s\n----\n%s\n----"(e,a,b));
        }
    }
}
