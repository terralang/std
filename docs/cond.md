Cond
====

The cond macro is a generalized form of a ternary operator.
It can accept an arbitrary number of condition-value pairs and a single default value at the end.
The conditions are evaluated sequentially until one that is true is found, or all of them are false;
the result of the cond form is the value corresponding to the first condition that was true or the default.

```terra
local cond = require 'std.cond'

local terra example(val: int)
    return cond(
        val == 1, 2,
        val == 2, 1,
        val == 3, 5,
        val == 4, 4,
        val == 5, 3,
        0
    )
end
```
