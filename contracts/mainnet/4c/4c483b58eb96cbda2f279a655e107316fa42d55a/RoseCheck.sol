
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 4ever Rose
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                  :0@Mi                                                                       //
//                                                                                i@B@@@B@                                                                      //
//                                                                              vB@B7   :B@J     ,:                                                             //
//                                                                            ,@BE        :@7 J@B@B@@@0i                                                        //
//                                                                           O@M            @@@U.   .L@B@Bqi                                                    //
//                                                                         vB@.            :BZ          .JB@B@BEj7::,..                                         //
//                                                                       .@B7             ;Bv                .7uPNZEOO@B@B@MPr                                  //
//                                                                      M@X              iBr                              .rF@B@X                               //
//                                                                    MBB     7NO80F1uuLvZr          rM@@BEL:                  r@@q                             //
//                                                                 ;B@M.    M@Or                  :OB@Xi  .riirrr;               OB@                            //
//                                                             .JB@Bk     rB@         :75qMM@B@B@B@B@     .UGu  ..    :Nv         @Bi                           //
//                                                   .7kM@B@@@B@BX.      YBj     .vEOMPu;:.        JBr       MB         B@        B@r                           //
//                                                7@@@@B@N2v7:.         LB7    vMZY,         .rvr    BE       @@         @5      i@B                            //
//                                              u@B@v.           .u@B@MOBi   .B2          ,NB@B@B@M   @L      r@         @B      @@L                            //
//                                             B@P              :B@8:.iq@M;  @:         ,Xqi     B@  .@B      UB         BL     @BP                             //
//                                            B@i                @B      7B@FuL                  @BuX8BM      BB        B@     @Bk                              //
//                                           7@B                 ,@:   Li  .8B@BM:            .r@B@L :@i     :@:       8@     @B2                               //
//                                           LB@                  ,@v   :ur   .JB@@@B@@@B@@@B@BM7    @B      @B       B@     @BX                                //
//                                            BB@:                  @G    :Uv      .::rii:,         @B      N@i     :B@     MBM                                 //
//                                             .X@B07i:,             NB.    :NL              :    L@8      ;BM     0BZ     L@@                                  //
//                                            :U@@@B@B@B@@@8U:        iBv     7O5          7k:  .B@i       @@    :@Bi      B@BSk7                               //
//                                          2@B@1.         iuO@B1:      B0      7BM2i,,iUOZr   OBk        B@.   O@B       B@P,7q@@@,                            //
//                                        :B@BJ                .YO@0i    BZ       ,YGMMqL    u@M         B@O  rB@r       i@B      O@@                           //
//                                       rB@B.                     ;Z@N:  Br               7B@.        GB@ B:5B@         @Bi       .B@:                         //
//                                      iB@B                          rZML@8             :@B,       7B@B,   @Bu         SBM          U@k                        //
//                                      B@Bj   ,iLUqG@BM2X0ZPXULi.       7B@i           M@:     .jM@Mr      :@         .B@            :@B                       //
//                                      vM@BGZ8qkJv:.r@BP      ,iv1u:       N@P.      U@r    ,SB@1:          U@        B@i              @B                      //
//                                                     .@@7        :J         L@Mi   BX    uBM7               B@      k@S                @B.                    //
//                                                       i@M                    iM@vB.   F@U                  UBu    r@M                  @B.                   //
//                                                   .:L1q@@B                      qBY .Bj                    7@B   r@M                    @M                   //
//                                             .7P@B@@@Bkr ,@B                       L@Br                     OB@  k@S                    FBN                   //
//                                         :u@B@BMJ:        7@L                        :8@r                  :B@Y.B@:                    MBM                    //
//                                      .M@B@Bi              B@                          ,8BF                B@BEXi                   .8@B;                     //
//                                      i@B@@                 BX                            u@M7           ,B@B                     r@B@:                       //
//                                        Z@@O                X@                              :N@M5i      JB@M                   .OB@u                          //
//                                          2@BZ               @7                                ,vEB@OU7@B@r                  rB@Z.                            //
//                                            7B@M.            0@                                     :7qB@,                 7@B7                               //
//                                              :@B@,           @.                                        B@               i@@,                                 //
//                                                .B@B:         MM                                        kB              @@:  :uO@   ru2k@  :ri5O:        .    //
//                                                   @B@.        @                                        8@            E@1 :8BS.OB.FP7. OBUkv:1M.   .:rikBk    //
//                                                    :B@G       F@                                       @B@0j:.   .iMBM.L@k.   J@r    .8:   BB7rUu5ui.YBu     //
//                                                      Y@B7      B7                                     5B. vq@B@@@B@M@.@U                   .    ,  .NP       //
//                                                        @BM      @r                                 vM@F          @, B@     u:     :u         ..:iUOq.        //
//                                                         uB@.     @E                          .iYZB@M;           @.  r.     B      @     iL52L,vB8i           //
//                                                          .B@v     Z@X.                 :L8B@B@B@B@1            @.  :      S1     kB rXZNYi     ;rY@7         //
//                                                            v@B      qB@OUi:,::r72PBB@@@B@BF7OB@B@M            @i  vY      @  .710B@BE.     i,.::Y0J          //
//                                                              0BM:      LB@B@B@B@B@Ok7:        0@@8           @M   Zi    .OBXu5v:    ijr.   Z@@i              //
//                                                                7MB@B@B@@@ZL.                   r@Bi         ;B    @, LMBOvuBU          .     iGk             //
//                                                                    .,,                          :@B         BP   :@@FL,     7Mq:    ., .:r7uuujr             //
//                                                                                                  B@i       .@  k@Ov@5         :FEr  :BP:7vLi,                //
//                                                                                                  iB@       7B1BS    r@S          i   :Bi                     //
//                                                                                       ::i::.      @B       8@B        ;Eu   ..        G@@:                   //
//                                    ,                                                 iv7rr72qO2   X@7    .BZ JB@L       .7  .@@@B@BBOq7                      //
//                                    @@qEUr      :;                                             @B1 .BO   Y@7    iBB@OL:       @@                              //
//                              .      Bv ;SBBEr   B@Zr                                           @BO @B  P@         .uO@B@B@BBOEq                              //
//                         XB@FS21211Ur@@     iEBM,@,.k@5                                         :@B@B@ L@   .LuUY7:                                           //
//                          8B         .r   .    :1B@   vBP   :                                     XB@@X@  YB@ui::ij:                                          //
//                iiLUujvr:  SB     .        :i     :     r@v F@7      iS:                            8@BZ.@M.                                                  //
//                @BLiri7vu5S1@N    ,ii       :k            52Ov@P      @1ku. @B;                     0B@B@,                                                    //
//                 @u          :      ,2.      .B        .i  iN  @j     7i :L@B:Z@.0Pr   .            0@BZ                                                      //
//        i7u1kSS27M@.     .,.          8:      :B        7i     i@      u.  i   .@B ,1i2B,           GBM                                 .ik. .iv@j  .:ir8,    //
//    ,GB@Fu7i,..,::v.       .rr         @.      uB        X.     B@ 7  BU2  .     ,   iB E:          O@1                          iX@,iYur@B;LL,k@rvuvi.@B     //
//      ZB,    ..              .k,       .@       @L        M      B1B7 .v     , .    .    G G        @BX                     L  5MrYBi,  ,B:    1v .   1G      //
//        28L     .,:::;;rrr;i:..@U       qM      ,@        NL     @BXB ,Uu  . .iM:   i  .  BZP       B@S                   v@@UB7                 .  .X;       //
//          iU1i                :B@rvvvr:  B,      BG       .B     ,  @8:ZY:    ..:. v:  r. . 2i      @BF                 .BL7@;      :.    ,    ,i :q7         //
//             rB@u           .vS:     ...u@Gvvr,  ,@        @r        @ .         ;qq   P     q:.    @@u              r r@. .   .    r    ,:  ,i,  r0vSF       //
//         .NB@@7.        ..ir7.         7@i  ,iLY7r@q       q@        G@.0.  .,::i:ri  5i   , P@L   .@Bu             j@8B       :    v    L  i.      .Bi       //
//           :q@Zi       ...           ,BM         @B7J0PUi  iB        :B:S:          r0F   ,:  u:   i@@v             B.O  :    ::   ,u    MO7.     .Uj         //
//              :FM8U:               .kZ:        i@O     :jFLS@;        @. i:   ..:i7vvXr   5  .@    L@Bv            r5   7.    L:    M  .r::... .vF7           //
//                  ,uM@BY         :JU,         M@:          @BPG0r     BJ ,EF           i O.  jBi   XB@;          vB@,   1.    Jv    B7:.       rBOvOv         //
//               .NB@B1Li      .:i7:          JBJ          r@@   iqB@Y  @u  PBr       ..:P@.    1    O@B;          OOG,   Z:    ;M  .iUM2i,         7B          //
//                 ,1@X.      .,.           7qv           B@7       ,PBZ@U    7L, .::irri.,J   O     @B@i          @:     Pu     @:::    ,:ii:,.   v7           //
//                    :28Pv.             .r7:           u@G            B@B@U    @M         iL.M      B@@i          Bi     7B   ,rX@P:           .Li             //
//                        ,rJZF,     ..,,,            i@M.           ,BO  r@B@L  .:i1E...,::B@       @B@i          @7      @::7i   .711J;:.     iZk1.           //
//                        r5@Bj                     iZ0.            MBr      1@B@:   :::i:: .B      .B@Br          @q   .rvP@O.         ,,:.    :Lqi            //
//                        ,rjJjSFu7i.            .;u7             U@N          :B@BB:        EB     .@M@7          8B.r5j:   :U57,           rU5;               //
//                              ,iLUkUjF@G7    :::          i.  u@M               UB@@N.      @E    :BBBL       :YO@@B@         .:i:,     .0@L                  //
//                                   :X@Br     .   .r.   .5@@Fu@Z                   :@@@Bu    N@:   :@M@u .r1@B@B@7  :M@Bi   ,          .:iJZ5                  //
//                                   iv77JSXqXXFF7rB@.rG@Bur@Bv  :L::.                .S@B@O:  B@   :BMM@B@B@ML.        LB@NrM@U27:.FBPJu7i                     //
//                                               ,B@B@BU.  .:  :i2B@LkEPr@Bv,            7B@B@7BBU  .@MMBv,                ,rJE. :7ju@G,                        //
//                                               ,,      :GN:.:::..,   .rM@.YPj            .OB@B@B   BMM@                                                       //
//                                                       ,U@B7     ..         iO5     .;uGMMB@B@B@Bi @MMB:                                                      //
//                                                    7k02;.        .iLv,       rBLL@B@@BkL:.   S@@B@MOO@2                                                      //
//                                                 rBB:     ...        ,u0i  .rUuFB8.             u@B@OOB@                                                      //
//                                                  ,qB     .,rY5L,      :@B2ri.  r5                YB@8BB.                                                     //
//                                                 rr.           :JPY ,vv: @1     :M                 ,BMO@5                                                     //
//                                               rL    .,:iii.     iBB:    58     iM                  @BMB@                                                     //
//                                              F@v,        .r5k:ri  @     LN     7O                  X@OM@L                                                    //
//                                                u@8        .:MM    M:    7U    :Ou                  ,BMO@B                                                    //
//                                              ;u:   .:,rrii. .0    N.    Y:   :@B,                   @@OO@u                                                   //
//                                            iZ:       ir@.   .5    u     Y    X 7                    i@MMB@                                                   //
//                                            BBr.   .:i  J    :;    i     : :,uu                       B@OMBB                                                  //
//                                             :@P .i:   ,,    7    :       jG@@                        :@BOMBL                                                 //
//                                            PY  ,.     .    .:       Pr i@L r                          GBMOB@.                                                //
//                                          uB.           .         .S0@1MG                               @BMO@B                                                //
//                                         @@v.;ri:@i .::8B   .iF :0Z:.@X.                                :@MMO@@                                               //
//                                        iq7ii,  PBX5JiFBX7J7:@@Yj.  ,                                    2@MMO@O                                              //
//                                                :     7:.   :1.                                           M@OOO@E                                             //
//                                                                                                           B@OOM@0                                            //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract RoseCheck is ERC721Creator {
    constructor() ERC721Creator("4ever Rose", "RoseCheck") {}
}

