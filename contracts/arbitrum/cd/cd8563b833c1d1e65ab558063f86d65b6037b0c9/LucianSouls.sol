// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC1155LazyMint.sol";
import "./DropERC1155.sol";
import "./PermissionsEnumerable.sol";

contract LucianSouls is ERC1155LazyMint, PermissionsEnumerable {
    // Store constant values for the 2 NFT Collections:
    DropERC1155 public immutable chest;

    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _chestAddress
    ) ERC1155LazyMint(_name, _symbol, _royaltyRecipient, _royaltyBps) {
        chest = DropERC1155(address(_chestAddress));

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(keccak256("MINTER_ROLE"), msg.sender);
    }

    function verifyClaim(
        address _claimer,
        uint256 _tokenId,
        uint256 _quantity
    ) public view virtual override {
        if (_tokenId <= 5) {
            //Material
            require(msg.sender == owner(), "Invalid");
        } else if (_tokenId == 6) {
            //Gem
            require(
                this.balanceOf(_claimer, 0) >= _quantity * 50,
                "You don't own enough Soul NFTs"
            );
        } else if (_tokenId == 15) {
            //Monster
            uint256 _multiplier = 2;

            if (_tokenId <= 9) {
                require(
                    this.balanceOf(_claimer, 6) >= _quantity,
                    "You don't own enough Summoning Gems"
                );
            } else if (_tokenId <= 12) {
                require(
                    this.balanceOf(_claimer, _tokenId - 3) >= _quantity * 2,
                    "You don't own enough Monsters before evolution"
                );
                _multiplier = 100;
            } else if (_tokenId <= 15) {
                require(
                    this.balanceOf(_claimer, _tokenId - 3) >= _quantity * 2,
                    "You don't own enough Monsters before evolution"
                );
                _multiplier = 500;
            }

            require(
                this.balanceOf(_claimer, 0) >= _quantity * _multiplier,
                "You don't own enough Soul NFTs"
            );
        } else {
            //Sword
            uint256 _multiplier = 2;

            if (_tokenId == 16) {
                require(
                    this.balanceOf(_claimer, 1) >= _quantity * 25,
                    "You don't own enough Soul NFTs"
                );
                _multiplier = 5;
            } else {
                uint256 v = 5;
                if (_tokenId == 17) {
                    v = 5;
                    _multiplier = 10;
                } else if (_tokenId == 18) {
                    v = 10;
                    _multiplier = 25;
                    require(
                        this.balanceOf(_claimer, 5) >= _quantity * 2,
                        "You don't own enough Dark Orbs"
                    );
                } else if (_tokenId == 19) {
                    v = 20;
                    _multiplier = 100;
                    require(
                        this.balanceOf(_claimer, 5) >= _quantity * 4,
                        "You don't own enough Dark Orbs"
                    );
                }
                require(
                    this.balanceOf(_claimer, 2) >= _quantity * v,
                    "You don't own enough Demon Horns"
                );
                require(
                    this.balanceOf(_claimer, 3) >= _quantity * v,
                    "You don't own enough Dragon Scales"
                );
                require(
                    this.balanceOf(_claimer, 4) >= _quantity * v,
                    "You don't own enough Degen Tails"
                );
            }

            require(
                this.balanceOf(_claimer, 0) >= _quantity * _multiplier,
                "You don't own enough Soul NFTs"
            );
        }
    }

    function _transferTokensOnClaim(
        address _receiver,
        uint256 _tokenId,
        uint256 _quantity
    ) internal override {
        uint256 _multiplier = 2;
        if (_tokenId <= 5) {
            //Material
            return;
        } else if (_tokenId == 6) {
            //Gem
            _multiplier = 50;
        } else if (_tokenId <= 15) {
            //Monster
            if (_tokenId <= 9) {
                this.burn(
                    _receiver,
                    6, //Gem
                    _quantity
                );
                _multiplier = 2;
            } else if (_tokenId <= 12) {
                this.burn(_receiver, _tokenId - 3, _quantity * 2);
                _multiplier = 100;
            } else if (_tokenId <= 15) {
                this.burn(_receiver, _tokenId - 3, _quantity * 2);
                _multiplier = 500;
            }
        } else {
            //Sword

            if (_tokenId == 16) {
                this.burn(
                    _receiver,
                    1, //Ingot
                    _quantity * 25
                );
                _multiplier = 5;
            } else {
                uint256[] memory ids = new uint256[](6);
                for (uint256 i = 0; i < ids.length - 1; i++) {
                    ids[i + 1] = i;
                }
                uint256[] memory amounts = new uint256[](6);
                uint256 v = 5;
                ids[0] = _tokenId - 1;
                amounts[0] = 2;
                if (_tokenId == 17) {
                    v = 5;
                    _multiplier = 10;
                } else if (_tokenId == 18) {
                    v = 10;
                    amounts[5] = 2; //orb
                    _multiplier = 25;
                } else if (_tokenId == 19) {
                    v = 20;
                    amounts[5] = 4; //orb
                    _multiplier = 100;
                }
                amounts[2] = v; //demon
                amounts[3] = v; //dragon
                amounts[4] = v; //degen
                this.burnBatch(_receiver, ids, amounts);
            }
        }

        this.burn(
            _receiver,
            0, // Soul
            _quantity * _multiplier
        );

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

    function openChests(
        uint256[] memory _chestIds,
        uint256[] memory _amountsToOpen
    ) external {
        for (uint256 i = 0; i < _chestIds.length; i++) {
            uint256 _chestId = _chestIds[i];
            uint256 _amountToOpen = _amountsToOpen[i];
            openChest(_chestId, _amountToOpen);
        }
    }

    function openChest(
        uint256 _chestId,
        uint256 _amountToOpen
    ) internal returns (uint256[] memory, uint256[] memory) {
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
        tokenIds = new uint256[](6);
        amounts = new uint256[](6);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = i;
        }

        uint256[5] memory _lotteryWeightSoul = [uint256(15), 30, 45, 8, 2];
        uint256[5] memory _amountsSoul = [uint256(1), 5, 10, 50, 100];

        if (_chestId == 3) {
            // MANEKI
            _lotteryWeightSoul = [uint256(14), 30, 40, 12, 4];
            _amountsSoul = [uint256(2), 10, 20, 50, 100];
        }

        uint256[5] memory _lotteryWeightMaterial;
        uint256[5] memory _amountsMaterial;

        if (_chestId == 0) {
            _lotteryWeightMaterial = [uint256(44), 35, 9, 9, 3];
            _amountsMaterial = [uint256(5), 3, 1, 1, 1];
        } else if (_chestId == 1) {
            _lotteryWeightMaterial = [uint256(44), 9, 35, 9, 3];
            _amountsMaterial = [uint256(5), 3, 1, 1, 1];
        } else if (_chestId == 2) {
            _lotteryWeightMaterial = [uint256(44), 9, 9, 35, 3];
            _amountsMaterial = [uint256(5), 3, 1, 1, 1];
        } else if (_chestId == 3) {
            // MANEKI
            _lotteryWeightMaterial = [uint256(58), 12, 12, 12, 6];
            _amountsMaterial = [uint256(10), 2, 2, 2, 2];
        }

        uint256 sum = 100;
        uint256 random = generateRandomValue();

        for (uint256 i = 0; i < _amountToOpen; i++) {
            random = random + 11 * i + (random % ((i + 1) * (i + 11)));
            uint256 r = random % sum;
            uint256 index = 0;
            uint256 s = 0;
            for (uint256 ii = 0; ii < _lotteryWeightSoul.length; ii++) {
                s += _lotteryWeightSoul[ii];
                if (s > r) {
                    break;
                }
                index++;
            }

            amounts[0] = amounts[0] + _amountsSoul[index];

            random = random + 33 * i + (random % ((i + 2) * (i + 23)));
            r = random % sum;
            index = 0;
            s = 0;
            for (uint256 ii = 0; ii < _lotteryWeightMaterial.length; ii++) {
                s += _lotteryWeightMaterial[ii];
                if (s > r) {
                    break;
                }
                index++;
            }

            amounts[index + 1] = amounts[index + 1] + _amountsMaterial[index];
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

