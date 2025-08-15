TODO: I want to make sure a service can only reference an app that exists
I would like to reuse nix typing to do so
I think the builder itself could become important as well
Do I want to have a test checking for unused labels or invalid references
or do i want to directly declare it and it auto-fills the yaml?
How to deal with CRDs here...
Do I want vanilla yamls => so you would just go for defining clusterrole twice in a binding? (if you chose cclusterrole instead of role)
Or do I want to create that role -> depend on that role -> and then assign it (binding gets created automatically)
  -> who does this binding then belong to? => someone needs to consume it, I guess the one who it gets granted for?? not sure - might need to be done manually
typing is essentially an option which is a submodule config which has expected fields
