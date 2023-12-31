// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Imsw.sol";
import "./IERC20.sol";
import "./AddressUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract MSWMutiCall is OwnableUpgradeable {
    IMSW721 public mswUnions;
    address public sellNft;

    // init
    function init() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        //main
        sellNft = 0x9452C79925a8d6ACED6a202F4bAD783E0252EFb5;
        mswUnions = IMSW721(0x25F982641bD7111dF3f9e0166CE24515937EdE52);
        //main test
        // sellNft = 0xfb07435Eca2AC0FC80c31B951f2D6346fd731007;
        // mswUnions = IMSW721(0x975AEB96c3C610fC97FEcfC681AD899e380C5CFb);
    }

    function setSellNft(address sellNft_) public onlyOwner {
        sellNft = sellNft_;
    }

    function setUnion(address union_) public onlyOwner {
        mswUnions = IMSW721(union_);
    }

    function checkInSellAndUpgrade()
        public
        view
        returns (
            uint[3] memory price,
            uint[3] memory currenyAmount,
            uint[3] memory max
        )
    {
        uint[3] memory cardIds = [uint(10001), uint(10002), uint(10003)];
        for (uint i = 0; i < cardIds.length; i++) {
            (, currenyAmount[i], , price[i], ) = mswUnions.cardInfoes(
                cardIds[i]
            );
            max[i] = mswUnions.minters(sellNft, cardIds[i]);
        }
    }
}

