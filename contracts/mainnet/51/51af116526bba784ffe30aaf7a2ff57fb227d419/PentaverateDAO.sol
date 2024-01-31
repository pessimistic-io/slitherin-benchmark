// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

//   _____           _                            _         _____          ____
//  |  __ \         | |                          | |       |  __ \   /\   / __ \
//  | |__) |__ _ __ | |_ __ ___   _____ _ __ __ _| |_ ___  | |  | | /  \ | |  | |
//  |  ___/ _ \ '_ \| __/ _` \ \ / / _ \ '__/ _` | __/ _ \ | |  | |/ /\ \| |  | |
//  | |  |  __/ | | | || (_| |\ V /  __/ | | (_| | ||  __/ | |__| / ____ \ |__| |
//  |_|   \___|_| |_|\__\__,_| \_/ \___|_|  \__,_|\__\___| |_____/_/    \_\____/

// The Pentaverate DAO
// Uniting five distinct powers in pursuit of decentralized decision-making and shared prosperity. But we are nice.

// Telegram: https://t.me/PentaverateDAO
// Website: https://pentaverate.co/

contract PentaverateDAO is ERC20, Ownable {
    constructor() ERC20("Pentaverate DAO", "5VERATE") {
        _mint(msg.sender, 420_690_000 * 1e18);
    }
}

