-- Top level app for a typechecker for the Raw TT syntax
-- plus
module TTMain.Main

import Core.Error
import Core.Syntax.Parser
import Core.Syntax.Raw

import System
import System.File

ttMain : String -> Core ()
ttMain fname
    = do Right inp <- coreLift $ readFile fname
             | Left err => throw (FileErr (SystemFileErr fname err))
         let origin = PhysicalIdrSrc $ nsAsModuleIdent (unsafeFoldNamespace ["Main"])
         let Right cmds = parse origin (rawInput origin) inp
             | Left err => throw err
         coreLift $ putStrLn (showSep "\n" (map show cmds))

usage : String
usage = "Usage: tt <input file>"

main : IO ()
main
    = do (_ :: fname :: []) <- getArgs
             | _ => do putStrLn usage
                       exitWith (ExitFailure 1)
         coreRun (ttMain fname)
               (\err : Error => putStrLn ("Uncaught error: " ++ show err))
               (\res => pure ())

