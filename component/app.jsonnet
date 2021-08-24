local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.maxscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('maxscale', params.namespace);

{
  maxscale: app,
}
