// SPDX-License-Identifier: MIT

/// @title The Snoop Dogg Passport Series
/// @author transientlabs.xyz

/*◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺
◹◺                                                                                              ◹◺
◹◺    __▄█▀▀▀▄▄▌_________________________________█▓▓▓▓▓▄▄_____________________╓▓█▀█,▄-          ◹◺
◹◺      _j██___║▀_╓▄▄▄__.▄▄__╓▄_____ ▄╓__╓▄▄▄▄,_____╫██__ ██▌___▄▄╥_____╓▄__,__▓██__└█└_        ◹◺
◹◺      __▀██▓▄____╙██▌__█_▄█▌ ██__▓█▀ █▄_██⌐ ██▄___╫██___▐██_╓██ ╙█─_▄█▌ ╙█¬_▐██ ______        ◹◺
◹◺      __▀▀▀█████⌐ ███▄_█▐██__║█▌▐██__██⌐██⌐_ ██__▄███___ ██─██─_j██j██___ _,███ █▄▄▄▄█        ◹◺
◹◺      _▄▀▀██▄╙███ █└██▄█▐██__██▌██▌__██▌██⌐_▐██___╫██___ ██─██__▐██▐██_▓███µ███_█╙╙██⌐        ◹◺
◹◺      █ ___██_ ██j█_╙███_██_╙└█▌╙██_╙▐█ ██▀▀▀└____╫██___▐██_██▌_└██_██_└ █▌_███_└__██         ◹◺
◹◺      █___▄▀▀__█▌▐█__╙██_╙██_▓▀__╙█▄,█¬_██⌐_______╫██___██▀_ ▀█▄▄▀__╙██,▄▀___██▌__]██_        ◹◺
◹◺       ▀▄  _ ▄█╙_   _    __,,,╓▄▄▄▄▄,__¬▀▀▌______,███µ▄█▀ _____ ______  _____ ██▄,█▀__        ◹◺
◹◺      __ └╙╙└ ____ ▄▄▓███▀▀▀╙└'       '└"¬w__,█__ ,-⌐⌐"7└^▀▀▀▀▀▓▓▓▄▄▄,_________ └└ ,__        ◹◺
◹◺          ____ "*ªKÆ████▀▀─____________________ "╬█"_ _______________ └╙▀▀██████▓▓▄ª*"└ __    ◹◺
◹◺                                                                                              ◹◺
◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺◹◺*/

pragma solidity 0.8.19;

import {TLCreator} from "./TLCreator.sol";

contract TheSnoopDoggPassportSeries is TLCreator {

    constructor(
        string memory name,
        string memory symbol,
        address defaultRoyaltyRecipient,
        uint256 defaultRoyaltyPercentage,
        address initOwner,
        address[] memory admins,
        bool enableStory,
        address blockListRegistry
    ) TLCreator(
        0xaD5AA880f860a88605c23869bA12428958d7cB3E,
        name,
        symbol,
        defaultRoyaltyRecipient,
        defaultRoyaltyPercentage,
        initOwner,
        admins,
        enableStory,
        blockListRegistry
    ) {}
}
