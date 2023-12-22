// contracts/Redeem.sol
// SPDX-License-Identifier: MIT
// Author: evergem.xyz

pragma solidity ^0.8.17;

import "./IERC721Enumerable.sol";
import "./Pausable.sol";
import "./Ownable.sol";

interface INFT is IERC721Enumerable {}

contract Redeem is Ownable, Pausable {
    INFT public gembot;
    INFT public magicAxe;
    uint8 public quantity = 3;

    event Redeemed(
        address indexed user,
        uint256 magicAxeId,
        uint256[] gembotId
    );

    constructor(address _gembot, address _magicAxe) {
        gembot = INFT(_gembot);
        magicAxe = INFT(_magicAxe);
    }

    function gembotSupply() external view returns (uint256) {
        return gembot.balanceOf(address(this));
    }

    function magicAxeSupply() external view returns (uint256) {
        return magicAxe.balanceOf(address(this));
    }

    function redeem(uint256 _magicAxeId) external whenNotPaused {
        require(
            magicAxe.ownerOf(_magicAxeId) == msg.sender,
            "You do not own this Magic Axe"
        );
        require(
            magicAxe.getApproved(_magicAxeId) == address(this),
            "You must approve this contract to transfer your Magic Axe"
        );
        require(
            gembot.balanceOf(address(this)) > quantity,
            "There are no Gembots left to redeem"
        );
        magicAxe.safeTransferFrom(msg.sender, address(this), _magicAxeId);
        uint256[] memory _gembotIds = new uint256[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            uint256 _gembotId = gembot.tokenOfOwnerByIndex(address(this), 0);
            gembot.safeTransferFrom(address(this), msg.sender, _gembotId);
            _gembotIds[i] = _gembotId;
        }
        emit Redeemed(msg.sender, _magicAxeId, _gembotIds);
    }

    function setQuantity(uint8 _quantity) external onlyOwner {
        quantity = _quantity;
    }

    function setGembot(address _gembot) external onlyOwner {
        require(
            this.gembotSupply() == 0,
            "You must withdraw all Gembots before changing the Gembot contract"
        );
        gembot = INFT(_gembot);
    }

    function setMagicAxe(address _magicAxe) external onlyOwner {
        require(
            magicAxe.balanceOf(address(this)) == 0,
            "You must withdraw all Magic Axes before changing the Magic Axe contract"
        );
        magicAxe = INFT(_magicAxe);
    }

    function withdrawGembot(uint256 _quantity) external onlyOwner {
        uint256 _gembotSupply = this.gembotSupply();
        require(
            _gembotSupply >= _quantity,
            "There are no Gembots left to withdraw"
        );
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 _gembotId = gembot.tokenOfOwnerByIndex(address(this), 0);
            gembot.safeTransferFrom(address(this), msg.sender, _gembotId);
        }
    }

    function withdrawMagicAxe(uint256 _quantity) external onlyOwner {
        uint256 _magicAxeSupply = this.magicAxeSupply();
        require(
            _magicAxeSupply >= _quantity,
            "There are no Magic Axes left to withdraw"
        );
        for (uint256 i = 0; i < _quantity; i++) {
            uint256 _magicAxeId = magicAxe.tokenOfOwnerByIndex(
                address(this),
                0
            );
            magicAxe.safeTransferFrom(address(this), msg.sender, _magicAxeId);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

