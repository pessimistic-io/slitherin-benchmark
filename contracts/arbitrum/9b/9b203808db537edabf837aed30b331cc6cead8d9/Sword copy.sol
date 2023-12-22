// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC1155LazyMint.sol";
import "./DropERC1155.sol";
import "./PermissionsEnumerable.sol";

contract Sword is ERC1155LazyMint, PermissionsEnumerable {
    // Store constant values for the 2 NFT Collections:
    ERC1155LazyMint public immutable souls;
    DropERC1155 public immutable chest;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _soulsAddress,
        address _chestAddress
    ) ERC1155LazyMint(_name, _symbol, _royaltyRecipient, _royaltyBps) {
        souls = ERC1155LazyMint(address(_soulsAddress));
        chest = DropERC1155(address(_chestAddress));

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(keccak256("MINTER_ROLE"), msg.sender);
    }

    function claimGold(
        address _receiver,
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _burnId
    ) public payable virtual nonReentrant {
        require(_tokenId == 0, "invalid id");

        uint256 quantity = 0;
        if (_burnId == 0) {
            //Soul
            require(
                souls.balanceOf(_receiver, 0) >= _quantity,
                "You don't own enough NFTs"
            );
            souls.burn(_receiver, 0, _quantity);
            quantity = _quantity * 10;
        } else {
            require(
                this.balanceOf(_receiver, _burnId) >= _quantity,
                "You don't own enough Swords"
            );
            if (_burnId == 1) {
                //Iron Sword
                this.burn(_receiver, _burnId, _quantity);
                quantity = _quantity * 75;
            } else if (_burnId == 2) {
                //Buster Sword
                this.burn(_receiver, _burnId, _quantity);
                quantity = _quantity * 300;
            } else if (_burnId == 3) {
                //Blood Sword
                this.burn(_receiver, _burnId, _quantity);
                quantity = _quantity * 800;
            } else if (_burnId == 4) {
                //Dainsleif
                this.burn(_receiver, _burnId, _quantity);
                quantity = _quantity * 2500;
            }
        }

        super._transferTokensOnClaim(_receiver, _tokenId, quantity);
        emit TokensClaimed(msg.sender, _receiver, _tokenId, quantity);
    }

    function verifyClaim(
        address _claimer,
        uint256 _tokenId,
        uint256 _quantity
    ) public view virtual override {
        //Sword
        uint256 _multiplier = 2;

        if(_tokenId == 0) {
            require(msg.sender == owner(), "Invalid");
        }else if (_tokenId == 1) {
            require(
                souls.balanceOf(_claimer, 1) >= _quantity * 25,
                "You don't own enough Soul NFTs"
            );
            _multiplier = 50;
        } else {
            uint256 v = 5;
            if (_tokenId == 2) {
                v = 3;
                _multiplier = 100;
            } else if (_tokenId == 3) {
                v = 6;
                _multiplier = 250;
                require(
                    souls.balanceOf(_claimer, 5) >= _quantity * 2,
                    "You don't own enough Dark Orbs"
                );
            } else if (_tokenId == 4) {
                v = 12;
                _multiplier = 1000;
                require(
                    souls.balanceOf(_claimer, 5) >= _quantity * 4,
                    "You don't own enough Dark Orbs"
                );
            }
            require(
                souls.balanceOf(_claimer, 2) >= _quantity * v * 3,
                "You don't own enough Demon Horns"
            );
            require(
                souls.balanceOf(_claimer, 3) >= _quantity * v,
                "You don't own enough Dragon Scales"
            );
            require(
                souls.balanceOf(_claimer, 4) >= _quantity * v,
                "You don't own enough Degen Tails"
            );
        }

        require(
            this.balanceOf(_claimer, 0) >= _quantity * _multiplier,
            "You don't own enough Gold"
        );
    }

    function _transferTokensOnClaim(
        address _receiver,
        uint256 _tokenId,
        uint256 _quantity
    ) internal override {
        if (_tokenId == 0) {}
        //Sword
        else if (_tokenId == 1) {
            souls.burn(_receiver, 1, _quantity * 25);
            this.burn(_receiver, 0, 50 * _quantity); //gold
        } else {
            uint256 _multiplier = 0;

            uint256[] memory ids = new uint256[](4);
            for (uint256 i = 0; i < ids.length; i++) {
                ids[i] = i + 2;
            }
            uint256[] memory amounts = new uint256[](4);
            uint256 v = 3;
            if (_tokenId == 2) {
                v = 3;
                _multiplier = 100; //gold
            } else if (_tokenId == 3) {
                v = 6;
                _multiplier = 250; //gold
                amounts[3] = 4 * _quantity; //orb
            } else if (_tokenId == 4) {
                v = 12;
                _multiplier = 1000; //gold
                amounts[3] = 8 * _quantity; //orb
            }
            amounts[0] = v * 3 * _quantity; //horn
            amounts[1] = v * _quantity; //scale
            amounts[2] = v * _quantity; //tear

            this.burn(_receiver, 0, _multiplier * _quantity); //gold
            this.burn(_receiver, _tokenId - 1, 2 * _quantity); //sword
            souls.burnBatch(_receiver, ids, amounts);
        }

        // Use the rest of the inherited claim function logic
        super._transferTokensOnClaim(_receiver, _tokenId, _quantity);
    }

    ///////////////////////////////////////////////

    /////////      Material 0 and 11-     /////////

    ///////////////////////////////////////////////

    event ChestOpened(
        uint256 indexed chestId,
        address indexed opener,
        uint256 numOfPacksOpened,
        uint256[] tokenIds,
        uint256[] amounts
    );

    function openChest(
        uint256 _chestId,
        uint256 _amountToOpen
    ) external returns (uint256[] memory, uint256[] memory) {
        address opener = msg.sender;

        require(
            chest.balanceOf(opener, _chestId) >= _amountToOpen,
            "You don't own enough Chest NFTs"
        );
        (uint256[] memory tokenIds, uint256[] memory amounts) = getRewardUnits(
            _chestId,
            _amountToOpen
        );

        uint256[] memory _chestIds;
        _chestIds = new uint256[](1);
        _chestIds[0] = _chestId;
        uint256[] memory _amountsToOpen;
        _amountsToOpen = new uint256[](1);
        _amountsToOpen[0] = _amountToOpen;

        chest.burnBatch(opener, _chestIds, _amountsToOpen);

        _mintBatch(opener, tokenIds, amounts, "");

        emit ChestOpened(_chestId, opener, _amountToOpen, tokenIds, amounts);

        return (tokenIds, amounts);
    }

    function getRewardUnits(
        uint256 _chestId,
        uint256 _amountToOpen
    )
        internal
        view
        returns (uint256[] memory tokenIds, uint256[] memory amounts)
    {
        tokenIds = new uint256[](1);
        amounts = new uint256[](1);

        tokenIds[0] = 0;
        amounts[0] = 0;

        uint256[5] memory _lotteryWeightGold = [uint256(15), 45, 30, 8, 2];
        uint256[5] memory _amountsGold = [uint256(1), 5, 10, 50, 100];

        uint256 sum = 100;
        uint256 random = generateRandomValue();

        for (uint256 i = 0; i < _amountToOpen; i++) {
            random = random + 63 * i + (random % ((i + 1) * (i + 41)));
            uint256 r = random % sum;
            uint256 index = 0;
            uint256 s = 0;
            for (uint256 ii = 0; ii < _lotteryWeightGold.length; ii++) {
                s += _lotteryWeightGold[ii];
                if (s > r) {
                    break;
                }
                index++;
            }

            amounts[0] = amounts[0] + _amountsGold[index];
        }

        return (tokenIds, amounts);
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
}

