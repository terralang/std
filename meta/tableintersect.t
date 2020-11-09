-- Performs an operation on every shared key of two lua tables
return function(a, b, f)
  for k,v in pairs(a) do
    if b[k] ~= nil then
      f(k)
    end
  end
end
