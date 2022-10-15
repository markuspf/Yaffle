module Core.Syntax.Decls

import Core.Context
import Core.Error
import Core.Evaluate
import Core.Check.Linear
import Core.Syntax.Raw
import Core.Check.Typecheck
import Core.Unify.State

parameters {auto c : Ref Ctxt Defs} {auto u : Ref UST UState}

  readQs : NF [<] -> Core (List RigCount)
  readQs (VBind fc x (Pi _ c _ _) sc)
      = do rest <- readQs !(expand !(sc (VErased fc False)))
           pure (c :: rest)
  readQs _ = pure []

  processDataCon : FC -> Name -> (Int, RawCon) -> Core Name
  processDataCon fc tycon (tag, RConDecl n rty)
      = do checkUndefined fc n
           ty <- check erased [<] rty (topType fc)
           tnf <- expand !(nf [<] ty)
           checkIsTy tnf
           arity <- getArity [<] ty
           qs <- readQs tnf
           let dinf = MkDataConInfo qs Nothing
           idx <- addDef n (newDef fc n linear [<] ty Public (DCon dinf tag arity))
           pure (Resolved idx)
    where
      checkIsTy : NF [<] -> Core ()
      checkIsTy (VBind fc _ (Pi _ _ _ _) sc)
          = checkIsTy !(expand !(sc (VErased fc False)))
      checkIsTy (VTCon fc cn _ _)
          = when (!(toResolvedNames cn) /= !(toResolvedNames tycon)) $
               throw (BadDataConType fc n tycon)
      checkIsTy _ = throw (BadDataConType fc n tycon)

  processData : FC -> RawData -> Core ()
  processData fc (RDataDecl n rty cons)
      = do checkUndefined fc n
           ty <- check erased [<] rty (topType fc)
           -- Add a placeholder for the type constructor so that we can
           -- check the data constructors
           arity <- getArity [<] ty
           let tinf = MkTyConInfo [] [] [] [] Nothing False False
           ignore $ addDef n (newDef fc n top [<] ty Public (TCon tinf arity))
           cnames <- traverse (processDataCon fc n) (mkTags 0 cons)
           -- TODO: Deal with parameters and universe constraints
           let tinf = MkTyConInfo [] [] [] cnames Nothing False False
           -- Re-add with the full information
           ignore $ addDef n (newDef fc n top [<] ty Public (TCon tinf arity))
    where
      -- I wanted to zip a Stream with a List...
      mkTags : Int -> List a -> List (Int, a)
      mkTags i [] = []
      mkTags i (x :: xs) = (i, x) :: mkTags (i + 1) xs

  processTyDecl : FC -> RigCount -> Name -> RawC -> Core ()
  processTyDecl fc c n rty
      = do checkUndefined fc n
           ty <- check erased [<] rty (topType fc)
           ignore $ addDef n (newDef fc n c [<] ty Public None)

  processDef : FC -> Name -> RawC -> Core ()
  processDef fc n rtm
      = do defs <- get Ctxt
           [(cname, i, def)] <- lookupCtxtName n (gamma defs)
                | ns => ambiguousName fc n (map fst ns)
           let None = definition def
                | _ => throw (AlreadyDefined fc n)
           tm <- check (multiplicity def) [<] rtm (type def)
           linearCheck fc (multiplicity def) [<] tm
           updateDef n (const (Just (Function (MkFnInfo NotHole False False) tm)))

  export
  processDecl : RawDecl -> Core ()
  processDecl (RData fc d) = processData fc d
  processDecl (RTyDecl fc c n ty) = processTyDecl fc c n ty
  processDecl (RDef fc n def) = processDef fc n def
