
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: BONSAI EDITIONS
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                             //
//                                                                                                                                                             //
//                .?!;#O'./1 ILq{1l.J&? ^},*M,`}^<dz. uo):u;                      'Zd,}#c`}]'u*- .;' ,mw":l'fk}                                 ?br'-1iqdaM    //
//                ,mk+0}.:&q`[n(vLI.C%] /W/.'.-h{+aX. }1^                          >['lx},Xb+ItI <8O `]_,c#/'`                                  ^!".cm!l~wk    //
//                 <}^   ,Wq!hMmCX^`L8? xWI'w/|#r<O/ ",.                                 '|Xi+bL:{8h >%p':_,                                        _[;LW-.    //
//                        `'!k&Jli l_;..'" ]%v'>'   "cY;                                     t#dI`?I ;0J"                                             :pB}:    //
//                           '^.  'Yb< Xk: Ua^ `?>. <0u,                                     }mr^                                                     ^vO[U    //
//                                ,Jr^ q$;     !MO,                                                                      .,^.^                            .    //
//                                 '.  0M: zO. ."'                                                                    I  iMC[Z>                                //
//                                         #M"                                                                        *] !#O_c!                                //
//                                         (h!                                                                        &L ^`'^                                  //
//                                                                                     "l^                            Y_;8dxd~"+I                              //
//                                                                                    `xMt                           ', I8m}Oi{h|";`               '{~.        //
//     .^.                                                                            ,z&j  !mr"                     0B,I8L^}|![Ic%).    ``     :zn>ZLI,'      //
//     zW{                                                    .. ,uX.                 ^nk]  !qw!                     qB( '<1bQlvrY8|''  'Wa'  -QjmUIUc}b{.     //
//     0MfWU ^^                                               hd.:Lbl                    {ht-dv,                     ]#" i&#WJ-wYl^'c&_ ,%q  .{bnJx^;^.`.      //
//     "lnBQ!Qz":^                                            hh';0h_.<}"       .' `va{  (#f>ci                     `  *a]Mc''?bXYb-Y%+]rX>~*j}or[xtku>d1}0    //
//     ["~*mif}1)`                                         :. ,; "xk-^no}       n8i^JMt:+jMn^                      z%?.%#{oj  ~mrX#[LB+qB! _#u<n>rwvhu[kr/h    //
//    >8_,;'   .'!:   !'                                  <k(.    .`..t#) `nj"  }M>"0#jraUm/.+wc"                  L8~;Bh_d?     v#[^,.p8;vn`.^tUcm1v][kuI<    //
//    '~_8dItp] ~mCI ]Wx;a0                               ]ov' +p^<ou'jo} iqal ^Q( "O*|j*(   f#Y,                  kB[l%O        l_"   l~.Mw;JL0O<I'  <bJ<0    //
//      >&L"nh} >0Ql ]Wf[@c'1f                         ici]*n. fa^`<!:I>^ ipkI I#Q ^cb>-X-   [ht`                  o@{;8c                .MQIdLnL;    ^0U1%    //
//      .:`'<]^ .;:.  " I&Yi&C >0f l:               +{^(h_,C). c*] .1k}   lqw; <WQ      >fi./0>  .m*l          _C+.*@} '                  i,!hv^,        ^+    //
//                         +8z ]a|,CLI             ^nQlitl     _X;  l{;lcu>0al IWw  ^fXIf&f'UM~  .a@!          [af`*@)                      ,/<                //
//                         "{i .`.1oc,.         ;~ ?bJ:                +pw>l+` lWp  :Qb1v%r.i_^   O%I>#L       nWf`m%]                                         //
//                                ix~'xi;.     ;wQ.1#z^                iZq< i[`I#O  ;wh)u&/        " IMp ._(,  uWt`:{'                                         //
//                                   ^i:h1.q"  !*J.;}+.                ._{: v*> ..  "zZi?c<          IWp "nq_  v&{.                                            //
//                                     "rII&'  `<:                          ro> |&).+f;              `}] :Xm<  u#+                                             //
//                                        ;U.                               i(" q%/^Jo[                  :zOi   .                                              //
//                                                                          ,dL'xh>']n;                   ,;                                                   //
//                                                                         "1oL`  '^)?                                                                         //
//                                                                       ^i)bt"LU'odMm_,                                                                       //
//                                                                       [bO#j`do:8ZYZd-I:                                                                     //
//                                                                    ;Xcc#JaU"k8,+`"zm+xt                                                                     //
//                                                                 'l!>OhLanl^,#B_na}Ownd] ?(,                                                                 //
//                                                                 !db{U&/>>i^^a%IXo!`inc^`cu,"`                                                               //
//                                                                 ipWxv&f'}ot''^ .^      >Q)`YY,                                                              //
//                           ' lJn_t![I                          '}wQ8x^<|>(#c^            '.-hnxj'                                                            //
//                          ibr-*Xz%f0?;[`                      ,_rozZ['?pv,"`               -wtkq` l[`                                                        //
//                       ~c .:",/tX8{  Ld,'                    'n*zMt"cO)0JI                   )*). |W( ^+;.`'^' ,.'['                                         //
//                       ZW,l1 lx]^,`  I`-W.                   .?WYr},zb-                      ;}`  v#< ?%X/Wnzn,w{:*?                                         //
//                      I!(,wq,1%mmrL}   dk                    m/Mw'?wmh]                           wo:'|MncoOaflp["of    :|+                   '](,           //
//                   r#i8C .~|^(&qp|       &^                 ^Wc  ^xk]                             mb ;mq~zJ!l,   ?M? WY ~WO'                  :Ym~           //
//              ^]! .wWi&J     ',^        'W!                 :ML)*(nh]                                 ..         j&< B*'~#Q'}ar`           ~c"!0Zvx<},       //
//              [dj` -).                   ` 'Ud'     >)I  .Y, ''?o};+^                                            j&~ %*'~MQ'}#x'        ^ZIrwlIJX1(xd+-`     //
//        "t(lUr1bx,C}'                      ^&b{Y`   n81. -#- 'n,'                                                [W[ %o'lQc.{*xxo('     [#(Cwi     /kxqI     //
//     1ZbYaC}oj^>;xMc^                      `dcXm>)zivW]..)W- -a_                                                 >#j Bo.    [hxzW|'     rM}tc,     .`1k!     //
//     "0O]Mz?L/1v)m('                         ;OZ]m8xvQij*_;. u#-                                                 .<^ Bb     .,^v8(''r_  J#i          [o_     //
//       .';^ "z8&Zd+                           ^:[#w<l>`U8_  :"!'                                                     %Q        z%1.l*Y  qo,          iw[.    //
//     :c+Lt/J?jz<'.                              ]bx'c#]ZM> >%x                                                       -<        Xo- l#Y  wp'                  //
//     )8J#Lmb-                                      ^Yk+1]` l8U                                                                 ..  _MU  ..                   //
//     _hzMr{zl                                      ^YQl  ;u;/_                                                                     f8/                       //
//       .^.                                          .    [*l                                                                       -0l                       //
//                                                     ~m{'/W>      '.                                                                                         //
//                                                     1o/'f&<[/   +oc                                                                                         //
//                                                     }o|'t&(wz ^+u8c.                                                                                        //
//                                                     (o/' !"hv`xbX8v}Y<               `](;                                                                   //
//                                                  l-">Y[':>^MO;kZvWnx%v,.~i.       .`';Ud_                                                                   //
//                                                  )Z+    0%;'`I#ZxornBx`lqC,       -8d(Ud_..                                                                 //
//                                                '"/k[!pt"qM,  lMQ  '[ni ~pL:>+.  ;z{&b(Yp100I                    `'                                          //
//                                                ]U}i`?hn^I, +`'+I    "?i?dL>hMI  +WC*Z?JL]0LIII.         .'      kC'                                         //
//                                                10> '_J{`!^,&[  '/w! -px1m{<#&; .[%U''   <wYIOw, :      ^no)    'oU' xI                                      //
//                                             ^i'(O~ ]O_ {o1/B[  ,Cpi ?dx^  ~*d^ii1&x     iY1,mo:;%-     :Yd]  nZ>ot.'8z '^                                   //
//                                            'tm, `[[nh- rW}to>  :0w; <mx`  +#/<Ba>X;        ^Za:?BL .II.;Uq_ .0U,". "8Llkz                                   //
//                                            "mp, :zwm*-'f<.       .        iO<{Bm            .. t$x iBq":Ym+ "Zc" . ,%Q<Mu                                   //
//                                       .l  .!!}. <ZQ<;'_h<.w]                 [M/               U@i l8Z  ;I  :mQ: kL'av+Wzl); .'                             //
//                                       _8_h_a.   <0v^-+n#<-8f                                   iu  !%Z      'Uz, ok  'j&z?h| un,                            //
//                                    .Q{U%#%[a' +u:   zx,^!f)"                                       !BZ           X}  `]` ?#jILn,  'bl                       //
//                                    :dQ".#8'. `fd_ 'xx;  Qh"                                        .,"               _d' ]&v-dn"  I#]  `                    //
//                                    ,dC^ &%{  ^jk] _dt.  LM;                                                         .|b" .'.<wX;}J}#c hC   ^xJ`  -b(,w0'    //
//                                 "1l'qL" >;+p' .'  1*/. j)`                                                           >Y.;JU.>ZXIXM<"'"&0   >wU",'n8vlqp`    //
//                                 [h/` L). 'Y*I;1`  .^' "boI                                                              ."^ .;,.YW<  'Wa:cr+dx>QxLBf;pk`    //
//                              .. ]k/`;hv'  ;c^/0[d0l;)l"dQ"                                                                 'x#1.Y&~/&~:I;az.'.}*vU8CI-|'    //
//                {q]. "^ 'uq; <pQI,/> laz'rw  "X0(8X'jM[ :"nc                                                                :YOi vW-OBI  +#x+Z/1Wcli;C~      //
//     ."  ''     {of`"Mo .?f. -Mz. '. Ihm'z&.  `"-U_ '^.  `kt                                                                !}; x0> Z%; !>O]]#c+C/c0(kj`     //
//     f&rIpU.![; `>" >WU     .?or (h?  ," u&+    ..    "fl>o~                                                                /*)'Ubi Z@;r&l .1orit1ZOtaC^     //
//     w#iloq-U%x^.jk[`i!<" IwZlII rW] '-' .I',wX.      z8-`>.                                                               'fWt,Jc, ch^qW:,ucwr?Yxdd}bd,     //
//     ,; '>_iU8r`^0B)' m$w _B0+J/ `I` )M;   .]&L.+pX^  ",.                                                                  .?{`   .f/' po"_oj  }mYk8})|`     //
//      '.   .<|i 'C%{..h$J.]Wn-ax!JZ> ")`   .(Q^ -hJ"                                                                            {[]oo^ Yv`1*/?YYhtnm_.;`     //
//     `pX    _z+ ./JI  Q$b'I(:>mc/#%]   [vI'UJ. ..:,                                                                            ~qQC&W,   ')*jnbrn-.{Y~O(.    //
//     ,o0 lji}aQ> ^tr^ x$h,.i_'.'<wo+   d%)^%o^<aX'                                                                             _ppp%vj] L)(*nXh{  .Uofb).    //
//     +%J.]Wz(*#) 'm&; ,{f]Ipa/.]c)!+}" xw^I8h^[%J'                                                                              I:^!IMql8dl_<Uarnx!0#ua(.    //
//     +8C,}%X)*#1 `Qh,  fBY;q8J.{zi YW+    +%k`(&u                                                                              <wdi ;WQ<Bo: '~((pQ>|r{h[.    //
//                                                                                                                                                             //
//                                                                                                                                                             //
//                                                                                                                                                             //
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract XBE is ERC1155Creator {
    constructor() ERC1155Creator("BONSAI EDITIONS", "XBE") {}
}

