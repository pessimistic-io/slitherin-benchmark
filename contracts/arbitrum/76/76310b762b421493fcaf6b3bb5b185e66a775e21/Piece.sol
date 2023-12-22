// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC1155LazyMint.sol";
import "./DropERC1155.sol";
import "./PermissionsEnumerable.sol";

contract Piece is ERC1155LazyMint, PermissionsEnumerable {
    // Store constant values for the 2 NFT Collections:
    ERC1155LazyMint public immutable souls;
    ERC1155LazyMint public immutable sword;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _soulsAddress,
        address _swordAddress
    ) ERC1155LazyMint(_name, _symbol, _royaltyRecipient, _royaltyBps) {
        souls = ERC1155LazyMint(address(_soulsAddress));
        sword = ERC1155LazyMint(address(_swordAddress));

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(keccak256("MINTER_ROLE"), msg.sender);
    }

    function burnSoulsGetPieces() public payable virtual nonReentrant {
        address receiver = msg.sender;

        uint256 quantity = 0;
        uint256 sword1Balance = sword.balanceOf(receiver, 1);
        uint256 sword2Balance = sword.balanceOf(receiver, 2);
        uint256 sword3Balance = sword.balanceOf(receiver, 3);
        uint256 sword4Balance = sword.balanceOf(receiver, 4);
        uint256 bonus = 0;

        require(
            (sword1Balance > 0 ||
                sword2Balance > 0 ||
                sword3Balance > 0 ||
                sword4Balance > 0),
            "You don't have any sword"
        );

        if (sword4Balance > 0) {
            bonus = 40;
            sword4Balance = sword4Balance - 1;
        } else if (sword3Balance > 0) {
            bonus = 30;
            sword3Balance = sword3Balance - 1;
        } else if (sword2Balance > 0) {
            bonus = 20;
            sword2Balance = sword2Balance - 1;
        } else if (sword1Balance > 0) {
            bonus = 10;
            sword1Balance = sword1Balance - 1;
        }

        uint256 multi = sword4Balance *
            8 +
            sword3Balance *
            6 +
            sword2Balance *
            4 +
            sword1Balance *
            2 + 
            swordsBonus(receiver);


        bonus = bonus + multi;

        
        uint256 result = resultRandom();

        bonus = (bonus * result) / 10;

        uint256 soulsBalance = souls.balanceOf(receiver, 0);
        require(soulsBalance > 0, "You don't have Souls");

        quantity = (soulsBalance * bonus) / 10;

        souls.burn(receiver, 0, soulsBalance);

        super._transferTokensOnClaim(receiver, 0, quantity);
        emit TokensClaimed(msg.sender, receiver, 0, quantity);
    }

    function verifyClaim(
        address _claimer,
        uint256 _tokenId,
        uint256 _quantity
    ) public view virtual override {
        require(msg.sender == owner(), "Invalid");
    }

    function _transferTokensOnClaim(
        address _receiver,
        uint256 _tokenId,
        uint256 _quantity
    ) internal override {}

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        require(from == address(0) || to == address(0));
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function generateRandomValue() internal view returns (uint256 random) {
        random = uint256(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    blockhash(block.number - 1),
                    block.difficulty
                )
            )
        );
    }

    function resultRandom() internal view returns (uint256 result) {
        uint256[6] memory _lotteryWeight = [uint256(3), 7, 70, 10, 7, 3];
        uint256[6] memory _amounts = [uint256(5), 8, 10, 12, 15, 20];

        uint256 sum = 100;
        uint256 random = generateRandomValue();
        uint256 r = random % sum;

        uint256 index = 0;
        uint256 s = 0;
        for (uint256 ii = 0; ii < _lotteryWeight.length; ii++) {
            s += _lotteryWeight[ii];
            if (s > r) {
                break;
            }
            index++;
        }

        result = _amounts[index];
    }

    function swordsBonus(address _receiver) internal view returns (uint256 swords) {
        swords = souls.balanceOf(_receiver, 7) *
            1 +
            souls.balanceOf(_receiver, 8) *
            1 +
            souls.balanceOf(_receiver, 9) *
            1 +
            souls.balanceOf(_receiver, 10) *
            3 +
            souls.balanceOf(_receiver, 11) *
            3 +
            souls.balanceOf(_receiver, 12) *
            3 +
            souls.balanceOf(_receiver, 13) *
            5 +
            souls.balanceOf(_receiver, 14) *
            5 +
            souls.balanceOf(_receiver, 15) *
            5;
    }
}

