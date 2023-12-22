// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Base.sol";
import "./ERC20Base.sol";

contract MonkeyBuilder is ERC721Base {
    IERC20 private _HighMonkeyCoin;
    uint256 private _price = 420;
    uint256 private _currentTokenId = 1;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address highMonkeyCoin_
    )
        ERC721Base(_name, _symbol, _royaltyRecipient, _royaltyBps)
    {
        _HighMonkeyCoin = IERC20(highMonkeyCoin_);
    }

    function mintNft() public {
        require(_HighMonkeyCoin.balanceOf(msg.sender) >= _price, "Not enough HighMonkeyCoin tokens");
        _HighMonkeyCoin.transferFrom(msg.sender, address(this), _price);

        _safeMint(msg.sender, _currentTokenId);
        _currentTokenId++;
    }
}

