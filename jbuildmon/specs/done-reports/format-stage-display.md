Here is an example of the --threads dislpay seen today. 

```
[11:20:21] ℹ   Stage: [agent7 guthrie] Build (7s)
  [agent8_sixcore] Unit Tests A [=====>              ] 32% 40s / ~2m 7s
  [agent7 guthrie] Unit Tests B [=========>          ] 54% 41s / ~1m 16s
  [agent8_sixcore] Unit Tests C [==>                 ] 19% 41s / ~3m 29s
  [agent8_sixcore] Unit Tests D [===>                ] 22% 41s / ~3m 8s
IN_PROGRESS Job ralph1/codex/implement-realtime-timing-fix-spec #25 [===>                ] 24% 52s / ~3m 39s
```

I want to modify this in a few ways.  We need tobe able to specify a format string for the stage status display lines.  This mechanism should be patterned after the existing --format option.
I want to be able to specify something like this:
BUILDGIT_PARALLEL_FORMAT='  [%%agent] %%stage  [%%graph]'

The user can also override the ENV setting with an argument to the --threads global option like this:
./buildgit --threads "  [%%agent] %%stage  [%%graph] %%elapsed / %%estimated" status -f

If the argument to the --threads argument is not present it will use a default string.

The order of precedence for this option is:

1. use argument to --threads, if it exists
2. use env setting BUILDGIT_PARALLEL_FORMAT
3. use default setting in the code.  For now, this default setting should be the current format shown on the screen now.

You will need to suggest names for other placeholder values other than the ones suggested above.  Let's use the %%string convention for specifying values.
Also, lets allow the use to use printf style strings where we can also speficy a maximum length of the value before the remainder is truncated.

