pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { InstaFlashV4Interface } from "./instapool_v4_interfaces.sol";

contract Variables {

    /**
    * @dev Instapool contract proxy
    */
    InstaFlashV4Interface public constant instaPool = InstaFlashV4Interface(0x1f882522DF99820dF8e586b6df8bAae2b91a782d);

}
