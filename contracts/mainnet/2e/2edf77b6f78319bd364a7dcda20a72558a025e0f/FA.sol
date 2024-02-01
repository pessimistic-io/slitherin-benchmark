
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Future Abstract
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
//                                                                              //
//    uZZZZZZZZZZZZZZuZZuZuZuZuZuZuuZuuZuZuuZuZuZuZuZuZZuZZZZZZZZZZZZZZZZZuu    //
//    ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ    //
//    ZZyZyyyyZyZyZyZyyZyZyZyZyZyZZyZZZZZZZyZZZZZZZZZyZZyZZZZZZZZZZZZyZZZZZZ    //
//    ZyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyZyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyZZ    //
//    yyyyyyyyyyyyyyyyyyyyyyyyyyyyyZyyZyyyyyyZyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy    //
//    yyyyyyyyyyyyyyyyyyyyyyyyyyyyZUY77<<<<774UyyyyZyyyyyyyyyyyyyyyyyyyyyyyy    //
//    yVyVVyVVVVVVVVVyyyyyyyyyyV=<_(..._..~..(-_(7Uyyyyyyyyyyyyyyyyyyyyyyyyy    //
//    yVVVVVVVVVVVVVVVVVVyyyWYi....(..._..~..(..._.(7XyyyyyVyVVyVVyVyyVyyyyy    //
//    VyVVVVVVVVVVyVVVVVVVyW]--..~._.~._.._..(..._.(_jdWyVVVVyVVVVVVVVVVVVyy    //
//    VVVVVVVVVVVVVVVyVyyWk@F(:...._>~~..._..(..._.(:(XWWVVyVVVVyVVVVVVyVVVy    //
//    VVVffffffffffffVVVXdN@SX:..~.(>.._(<~..(..._.(0dXWNXyVVVVVVVVVVVVVVVVy    //
//    VVfffpfpfpffpfffVVdHNMND...-.(o-..(..._(..(<<-JWHW@NWVVVVfVVffffffVVVV    //
//    VVffffpfpfpffpfffkMMNHB<_.~>._.._sdsc_.._.(-._(d@WM@dVffffffffffffVVVy    //
//    VfffpffpffpfpfpffW@MNE~~_((aJ+ggxQmqmugggJJo<<~_TMN@KVVVfffVVffffVVVVy    //
//    fffffffffffffffffV@M5qgNMMMMNNNMNWkwHHMMMMMMMMNas?MMWyyVVVVVVVVVVVVVVV    //
//    fppfpfpffpffffffVWMqMNMMMMMMHMMMHW(_dWMHM@M@MMMMMMKMXyyVVVVVVVVVVVVVVV    //
//    ppppfpfpffpffffVVyWdNMH@HHkHMMHHWfJi4futureabstractXyVVyVVVVVVfffpffpf    //
//    pppppppppffpfffVVyMdMM@@HgmWHHH#VudHcdddmgKgHWg@MM@NVVVVVffffppppppppp    //
//    pppppppppppfpfffVWMbTM@@HgmWV5jfuHMHHyXJ7WWmHWg@H9JMHfffpppppppppppppp    //
//    kkbbbbppppppppppWMmzVGJzI<<<<+WXHKHMNQv9+~~<<1&Jz6zdNWpppppbbbbbbkbbkb    //
//    qkqqkkkkkbbbbbbbbXMNmgmQkykXHdDd##HMdH#dHWXRdQmgQmMMWbkkkkkkkkkkqqkqkq    //
//    mmmmmmmmmqmqmqqqqkHkWHHHMdHMNMfN#@7=MMHdHMMHRHHWWWXWqqqmmmmmmgmmmmmmmm    //
//    ggggggggggggggggmmHHXpbpkMdNNH3H$((._JHvKMNNWXfffWWggggggggggggggggggg    //
//    @@g@@g@g@gg@ggggggmkHfNmHHWMMgADv07fC7wJqdNNdpbWHkHgggg@g@g@@g@@@g@g@@    //
//    @@@g@@g@g@@@g@@@@@gHkWMMMNUW0d((-+.n.-++OUHHWHHMHXHg@@@@@@@@@@@@@@@@g@    //
//    @@@@@g@@@@@@@@@@@@@gmHMMMNKHMHSkOyuRwhhddMHHWNM#WHg@@@@@@@@@@@@@@@@@@@    //
//    @@@@@@@@@@@@@@@@@@@@@gHMMMHHHWw_,R(R(OJJXHHgMMMHg@@@@@@@@@@@@@@@@@@@@@    //
//    @@@@@@@@@@@@@@@@@@@@@@HKMMHHMMMMMMMMMMMMMMHHMMHH@@@@@@@@@@@@@@@@@@@@@H    //
//    @H@@H@@H@@@H@@H@@H@@H@@@HMMMMMMMMMMMMMMMMMM##WH@H@H@HH@H@H@H@H@H@HH@H@    //
//    HHHH@HH@HHH@HH@HHHHH@HHHHHHMMMNNMMMMNNNMMMMWHHH@HH@HH@HHH@HHH@HH@HH@HH    //
//    HHH@HHHH@HHHHHH@H@HHHHH@HHHHMWHMMMMMHMMHHWHHH@HH@HH@HH@H@HH@HH@HH@HH@H    //
//    HHHHHH@HHH@HH@HHHH@HH@HH@HHHHHHHNMdHNHHMMHHHHHHHHHHHHHHHHH@HHHHHHHHHHH    //
//    HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHNMMWHHHMMHHHHHHHHHHHHHHHHHHHHHHHHHHHHH    //
//    HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHMMM#HHHMHHHHHHHHHHHHHHHHHHHHHHHHHHHHH    //
//    H#HHHH#HHHHHHHHHHH#HH#H#HH#HH####M#M####HHHHHHHHHHHHHHHHHHHHHHHHHHHHHH    //
//    H############################################H#HH#HHHHHHHHHHHHHHHHHH##    //
//                                                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////


contract FA is ERC1155Creator {
    constructor() ERC1155Creator("Future Abstract", "FA") {}
}

