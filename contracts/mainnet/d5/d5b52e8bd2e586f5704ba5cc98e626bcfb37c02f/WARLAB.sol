
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: WarGames Labs
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                               //
//                                                                                                                               //
//    Q@BB@O#@Z@@d@@R@@d@@Z@@q@Q$@QQ@q@@3@@Z@@d@#$@@d@#d@BQ@dB@R@@O@@O@@0@@$@@g@#Q@#B@g@@$@@8@@Q@@8@@83wIIw3O@Z3eQzXQKQBZ@E@3    //
//    RBE0QK$QXQQIQQ3QQIQQzQQyQOqQddQyBQVQQzQQXQ8qQQIQ0XQ0dQeEB3BB3BB3BBMBBZBBd#Q$#8$#O##O##E##$##E##dHqOMweIQzKR@Zd@XdRzQKQH    //
//    RB0EBK$BIBBIQBeQQXQQXBBwQRMBOOQwBQyQQzQQzQQ3QBIB$IB0OBIEB3#B3BB3BBqBBMBBdBQ0#g$#O##O##E##0##E##dewIMMRd#zeeQzXQZQBd@0@O    //
//    $      .H##c##y      w#3#Q0#g8#K##e##H##q##O##,            :M##d##O##R##0##Q#BQ#$##$@@g@@8@#$@#OeyIeweI#MOR@M3QXdOzQKQK    //
//    O?      xQ  IQ       0,         ^8*         `$      iT      ^Q.         :#r        `      d#^          Zw          \0@R    //
//    RB       ^   H      -.    'I     e-     ?    \      ^ :-  ';KV     3     Q     vr   \T     R     )      r     3     VQe    //
//    E#Z                              K-    .IRVrwQ      =,      ^Q^          8     $q   RB     O           YX`       ,~#0@R    //
//    Q@B:       x       \      )Q     R!    :O@@$@@      T)      \_    `Q     #     BR   Q#     g     Ze` ``ex     ?     IQK    //
//    RB00      Oe`     Tg-            O_    .eQQMQu              **           Q     $Z   gQ     8           ;T           d@R    //
//    EB0$Q}eqi$BKQZYqqVBBi_`    `~yq}BBwqHxHQIBQx,    ;r_`     `IM#QcZZuZZcZ0d#gXZK3#O##O##3ddXQ#08dcx\xxv}XQzITH\v3vcwYQ38e    //
//    Q@B#@E#@O@@R@@0@@R@@Rg^'`  `-*Qd@@d@@O@@O#^   `_x?,-...''.*#0@@E@@$@@$@@8@#B@#B@8@@8@@Q@@Q@@Q@@8RqORqRO@ZOR@dd@dQBZ@0@E    //
//    EB00B3$BKBBKQQqQQ3QQeQB~-`   .!*QQXQQeQQ?`   `:\!-.``'.-:iBBqBBqBBZBBZ##O#Q$#8$#O##R##0##$##0##dewKezeIQzXeQXXBXdOzQ38I    //
//    EB$$BHgB3BB3BBMBBHBB3BB;^,`   .~3BIBB3$^    `:*-`',!^vcZQM##M##M##d#Bd##R#Q$#Qg#E##E##$##$##0##dKwIezeXBwXH#dd@dQBZ@0@R    //
//    EB$$BqgB3BB3BBqBB3BB3BB;~;!.` `_^ReQBw=`  `._~-,^vuVqQH$BM##M##M##Z#Bd##R#Q$#Qg#R##R##$##$##0##ddMORqOd@HHeQXXQXdOXQKQK    //
//    Q@B#@0#@R@@E@@$@@E@@E@@dZ?:_...'''......-,,:!^)}Kd@#Q@EB@$@@$@@0@@$@@g@@8@#B@##@Q@@Q@@Q@@Q@@Q@@gqwIeweIQzIKQze#dQBd@0@E    //
//    0B$$Bq8BHBBHBBMBQqBBHBBz).          `````'.^iydQ8HBgEBq$BZ#BMBBZ##d##O##R#Q$#Q8#E##0##$##$##$##dKyIeweZ@ZOR#dZBXdOzQKQe    //
//    0#$$BM8BqBBqBBMBBHBBqBBx,`            ``--_?IQMB8qB$EBH$BZ#BZ##Z#Bd##O##R#Q$#Qg#E##E##$##$##$##dKHdRMqXQzIKQzIQZQBZ@0@E    //
//    B@##@$#@E@@0@@$@@0@@$@@c^:.'`        ``.!^^\w@$@#0@#B@0#@$@@$@@$@@g@@8@@Q@##@##@Q@@Q@@Q@@B@@Q@@gEwIKwKXQXdR@Zd@IZOzQKQI    //
//    0#$$#Z8BqBBMBBdBBMBBqBBV**^,.        ``-~xx^*dZB8M#g0#M$#d##d##d##d##O##E#Bg#Q8#0##0##$##$##$##dKweKXOO@MeKQzzQz$BZ@E@E    //
//    $#gg#dQ#M##Z##d#BZ##M#Q^^:^;-`       `._^x:,!r3#QZ#8$#Zg#d##d##d##d8EXZqIR0g#QQ#0##$##g##g##g##dKKREIezQzIq@dd@MdOwQKQK    //
//    $#$g#dQ#Z##Z##d#BZ##Z#I,.'-;,.`      `.,*\_-,!;dQZ#8$#dg#O#Qee}^!_..''''`'.-!?w$E##$##$##g##$##0EeXeyee@MOZQzXQXdBZ@E@R    //
//    B@##@g#@$@@$@@g@@$@@$@x,---,-'.`    `.,,=*!-_!~?~.-~vIu}?:'``          ```````'-:*VM@@B@@B@@Q@@EKyIe3RdBwIIQZd@dgOwQeQK    //
//    g#88#OQ#d##d##O##d##d0*:,::.``'--..'-,,-_!*!,=^\r`  `.--'               ```  ```_.'_\q$##8##g##deXdOwIXQHOR#zIQzdBZ@0@M    //
//    $#88#OQ#d##d##O##d##d$\;=^=.'``.:~^^~_'.-:*\^rxx:    ``.'                 ``` `.''`',:=IBQ##g##dd3IIw3d@IIeQXZ@dQRzQKQd    //
//    B@##@8#@g@@g@@8@@g@@g@Iv)v*!:,-..,=!,-_,:;vuxYx=.    ```                  ````...``.__-,*d@@B@@gKyIKMdXQzeR@MIQzZgZ@0@q    //
//    g#8Q#RQ#O##d##R##O##O##Kyuux)*^^^^^^;^^*?ucv)='``    ``               `` ``'..,,'`'....-!^e#8##dIyMOyeX#MOIQzX@dQgzQKQO    //
//    8#QQ#EB#R##R##E##R##R##R8ixxiY}}YYvviTcci^-```      `'`              `````.-,::.  `'`..-:;^38##dMHIIwZd#wX3@ZMQzd$Z@0#I    //
//    Q#QQ#EB#R##R##E##R##R##Rz_---.-:*vxx\^:'`     ```  `._`         ````''..-.-_-.    ``'-__,:=^e##$qyIHM3XQKOdQzz#dQgzQeBR    //
//    #@##@Q#@8@@8@@Q@@8@@Q@@0;.````````'.`        `'.`` `-_`        `''``'`..--.'`     `..--,,,!^?Q@RIyMZye3@KXIBZd#zMEq@0#e    //
//    Q#QQ#$B#E##E##0##E##0##T~,..'```````     `'``'.. `''-_`    `''...'`    `````''````.--.-,:,!~*}#dKqIXzR3QwqR#zzQdQQzQe#R    //
//    Q#QQ#$B#0##0##$##E##0##u^!,--..'''```  `'`  ``.'``-,:_`   .-_-'`            ``'..`'.,-.-:!!!*x8OdVXM3IzBZ3IQMd#zMOq@0BI    //
//    #@##@Q#@Q@@Q@@Q@@Q@@Q@@T*~!:,,,_-.'''`'-`   `.-,.-!!:-`'_,::,`         ```'....-.`',~,`-!^==?xZgzVqqyId#wXZ@zzQqQBXQK#E    //
//    Q#QQ#$B#$##$##$##$##$##XYxr^~!,_-.-----````.,!!-``.,:_`.!;^:.'``     `.-`---.'``.-,;^,.,=*~*i\IZXqeIeZwQHOe8Id@XZdq@EQX    //
//    RHHRHH0HH033$3Z03Z$3dE3dK\??r=:::::!::,,,,!~^:'.,!~^^,..:^=:__-.``  '-.'',-...-,!~^^_--:~r!^\\wHdywMIXK@XXK@qzQ3QBXQe@R    //
//    xw)xw?\wxvw}\VYxyTic}}uTuTxr)\*^^^^;~==~~;;^!-_!^!~r!.,!*^:!==!:,___::...,..-_!^=::-.,=;*?^)xiuqVwHHVHMQyMdgwK@KMdK@EQI    //
//    VxXIiyKVTewuXXVyezwewIzXKzHT}Yixv?r*^^^***^=:!*r~!^~'.!;=:!~^^r**^^^^!-,!,``'_;-.-!,~^*rxxvv?iY```-*XHzQZII#ZK8IQBXQ3@R    //
//    iwc}TwTuwcVcwTzVccwyTKcVyIweIiixv\\??)rrr))r)\v)?\*,,==,,~~=*****^=!:=~=,.-,!*^,:~^^*r?xY?^*\x)   `.!VM#wIRByX@MMdK@R8X    //
//    XyXcXyeyzyeIyzKXyX3zyIMwy3HwzMzVuuTT}Yixxxxxxv\vr^^;~:,,!^^~~^;^^;!!!~==~^**^^!:~;^;*rvi;!;^*Y_   `.!}IqHdX8ZZ8y8BK83@R    //
//    dOdddRddORdOEOZ0ROZ$0OZg$OMQgOZReuTTuuuuTTT}TTYv**;!,_,:~r*~!~^^^^^;==.''.---_.-,!*r\?*;!^*^ix`  `-:*V8Qdeq#Vw#Zqde@d8X    //
//    3yVXHwyzHIVX3Hcz3Myy3MXc3ZecIZqTXddcwyXwwyyyVi);!:,,,,!~**^!::::!=!::_---,=;!!!;*?v)r!!)*x)ic-  ':~*}MycZZzeqdQw$BK8H@R    //
//    EEOZd8ZOqgEdZRQddZQ0dq$QdM0Q$ddQQOH8Q0wrr=~\Y*!,__-_,:;*r*^,,,,,,,:!~^*^***!!^??r!!*^~v}YiTc!``.:)xu30QQMZQQMTQdOZX@d$I    //
//    ddQdOM$8qOOQ$dZ$QRZdQQdd0QgZZQQEqRQQZMc-...-!^,-..--,!=;;=_`'-_::!!!~!!;~!,'-^::;^xYviyuY}c!''-~xce0QZMQQgMRQQZIRBKgH@d    //
//    HqdggHMdQ$HdO8g3ZEQ$HZ$8$KdQQ$KR88$Kz?.     .,``   `.-_,.     ``'-!**^**r?vxxv)vxTVu}v?*xc*!~*iwMQZdQ8$3dQQEHO88Mdw@d$3    //
//    QQdMRQQdMOQQEMOQQ$ZdQQQHdQQQqdQQ0}``       ``````   ``.`         `'.-:=^)vxY}TTcu?;,_!^YyxvYzd8dQQQ03BQQ0KQQQ0H$QQRE3@Z    //
//    Md8Q$MZgQQMq$QQRMRQQ8qdQQQdZ8QQq.       ```     `'``.'-          `-_-----_,::!!!_-_:;)yIKdEg#QQ0KQQQ8egQQQqdQQQd3QQQ$$H    //
//    QQMH0QQ$qZQQQdH$QQQqZQQQR3gQQQI:` ``   -.```   `._-._,_'.'.``  `.,:!=!!!:::::,,,::=rI8O#QQQKdQQQ$zQQQQqMQQQ0e0QQQM3QQQ0    //
//    qdQQQZH0QQQMqgQQ83MQQQgKRQQQ0eQB$RXHMKIx;:,,,:!;^^^r?i\??))r^^**)\x}TicVzXKVHddR0HB#QQM3QQQQHOQQQ8X$QQQ$IQQQQd3QQQQHZQQ    //
//    QQ8Hd0QQ8HZ0QQQ3qgQQQHqQQQQ3MQQQQMZQQQQqOg$$$K$$$g8K0QQQQIgQQQ8wQQQQQwQQQQQwQQQQQygQQQQXgQQQQI$QQQQI$QQQgK0QQQ$H0QQQ0H0    //
//    OZZQQQgHdQQQQMZQQQQdHQQQQE3gQQQQIRQQQQHdQQQQdZQQQQgIQQQQQwQQQQQzQQQQQwQQQQQKKQQQQEzQQQQQwQQQQQzQQQQQKRQQQQMZQQQQdHQQQQd    //
//    0QQQRZdQQQQdqQQQQ0M0QQQQMdQQQQE3QQQQQeRQQQQO3QQQQQzQQQQQddQQQQQzQQQQQyQQQQQQzQQQQQzQQQQQRqQQQQQwQQQQQqOQQQQE38QQQ83OQQQ    //
//                                                                                                                               //
//                                                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract WARLAB is ERC1155Creator {
    constructor() ERC1155Creator("WarGames Labs", "WARLAB") {}
}

