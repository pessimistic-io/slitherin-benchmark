//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";

interface IERC1155 {
    function burn(
        address account,
        uint256 id,
        uint256 value
    ) external;
}

contract SmolRacingRedemption is Ownable {
    mapping(uint256 => uint256) public tokenIdToRedemptionQuantity;

    address public ERC1155Address;
    address public ERC20Address;

    function redeem(uint256 _tokenId, uint256 _quantity) public {
        require(
            tokenIdToRedemptionQuantity[_tokenId] > 0,
            "Token does not have magic redemption number!"
        );

        //Burn their 1155
        IERC1155(ERC1155Address).burn(
            msg.sender,
            _tokenId,
            _quantity
        );

        //Send them their erc20
        IERC20(ERC20Address).transfer(
            msg.sender,
            tokenIdToRedemptionQuantity[_tokenId] * _quantity
        );
    }

    function withdrawMagic(uint256 _amount) public onlyOwner {
        //Send them their erc20
        IERC20(ERC20Address).transfer(0x482729215AAF99B3199E41125865821ed5A4978a, _amount);
    }

    function setTokenRedemptionQuantity(uint256 _tokenId, uint256 _quantity)
        public
        onlyOwner
    {
        tokenIdToRedemptionQuantity[_tokenId] = _quantity;
    }

    function setAddresses(address _ERC1155Address, address _ERC20Address)
        public
        onlyOwner
    {
        ERC1155Address = _ERC1155Address;
        ERC20Address = _ERC20Address;
    }
}

