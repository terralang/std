-- Performs an operation on every key of both tables, but only once for shared keys
return function(a, b, f)
  for k,v in pairs(a) do
    f(k)
  end
  
  -- Only call the function for keys in b that AREN'T in a
  for k,v in pairs(b) do
    if a[k] == nil then
      f(k)
    end
  end
end
