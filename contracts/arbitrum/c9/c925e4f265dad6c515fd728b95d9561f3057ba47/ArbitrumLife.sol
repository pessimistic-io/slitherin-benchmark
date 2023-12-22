// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./CoordSet.sol";
import "./CellMap.sol";
import "./CellMath.sol";
import "./ExpandableMap.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

struct BuyRequest {
    // Pixel coords are packed into uint32 for efficiency
    uint32 cell;
    address owner;
    uint8 color;
}

contract ArbitrumLife is
    Ownable,
    CoordSet,
    CellMap,
    ExpandableMap,
    ReentrancyGuard
{
    // Tax for reselling or repainting that goes to the dev
    uint8 private immutable resellTaxToDev = 1; // percentage
    // Tax for reselling that goes to the previous owner (on top of 100% of
    // their initial deposit).
    uint8 private immutable resellTaxToOwner = 9; // percentage
    // pre-computed values for exponentially increasing price,
    // set in the contract constructor.
    uint256[256] private _prices;

    // Anyone can listen for the following events or use eth_getLogs to
    // reconstruct the entire history. Note that color values are not stored in
    // the contract, because they do not matter for the economic side of things.
    // Colors only persists in logs.

    // New cell bought for base price
    event NewCellBought(uint32 cell, address owner, uint8 color);
    // Cell repainted by its owner
    event CellRepainted(uint32 cell, address owner, uint8 color);
    // Cell repainted by another user
    event CellResold(
        uint32 cell,
        address oldOwner,
        address newOwner,
        uint8 color
    );

    constructor(
        uint256 basePrice,
        address developer,
        uint32 unlockedMapSize,
        uint16 mapUnlockStep,
        uint8 mapUnlockPercentage
    )
        ExpandableMap(unlockedMapSize, mapUnlockStep, mapUnlockPercentage)
        Ownable(developer)
    {
        // Precompute prices exponentially increasing with each resell
        uint256 priceAccum = basePrice;
        uint256 totalPercentage = 100 + resellTaxToDev + resellTaxToOwner;
        for (uint i = 0; i < 256; ++i) {
            _prices[i] = priceAccum;
            priceAccum = (priceAccum * totalPercentage) / 100;
        }
    }

    // Withdraw function for developer
    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // Compute the total price without buying. Used by the app to give a price
    // estimate before the user buys
    function estimateCells(
        BuyRequest[] calldata reqs
    ) public view returns (uint256 price) {
        uint reqsLength = reqs.length;
        uint total = 0;

        for (uint i = 0; i < reqsLength; i++) {
            (uint toOwner, , uint toDeveloper, , ) = estimateRequest(reqs[i]);
            total += toDeveloper + toOwner;
        }

        return total;
    }

    // The main function of the contract the users interact with.
    function buyCells(
        BuyRequest[] calldata reqs
    ) external payable nonReentrant {
        uint reqsLength = reqs.length;
        uint toDeveloperTotal = 0;
        uint toOwnersTotal = 0;
        uint32 newPixelCount = 0;

        for (uint i = 0; i < reqsLength; i++) {
            BuyRequest calldata req = reqs[i];
            (
                uint toOwner,
                address cellOwner,
                uint toDeveloper,
                uint8 resells,
                bool alreadyBought
            ) = estimateRequest(req);

            toDeveloperTotal += toDeveloper;
            toOwnersTotal += toOwner;

            if (alreadyBought) {
                // Cell is already owned
                if (msg.sender == req.owner) {
                    // if *we* own this cell
                    // We don't need to update address map, because ownership is
                    // not going to be changed
                    emit CellRepainted(req.cell, msg.sender, req.color);
                } else {
                    // if someone else owns this cell
                    // Nullify old owner's ownership of the cell
                    _set(req.owner, req.cell, 0);
                    // Set ourselves as the cell owner
                    _set(msg.sender, req.cell, resells);
                    payable(cellOwner).transfer(toOwner);
                    emit CellResold(req.cell, req.owner, msg.sender, req.color);
                }
            } else {
                // first buy
                {
                    (uint16 y, uint16 x) = cellToCoords(req.cell);
                    _setCoords(y, x);
                }
                _set(msg.sender, req.cell, 1);
                newPixelCount++;
                emit NewCellBought(req.cell, msg.sender, req.color);
            }
        }

        require(
            msg.value == toDeveloperTotal + toOwnersTotal,
            'Amount does not match'
        );

        paintNewPixels(newPixelCount);
    }

    function getResellPrice(uint8 resells) public view returns (uint256) {
        return _prices[resells];
    }

    function estimateRequest(
        BuyRequest calldata req
    )
        private
        view
        returns (
            uint toOwner,
            address owner,
            uint toDeveloper,
            uint8 resells,
            bool alreadyBought
        )
    {
        require(req.color != 0, 'Color code must be in range [1,255]');

        {
            (uint16 y, uint16 x) = cellToCoords(req.cell);
            require(isUnlocked(y, x), 'The pixel is not within unlocked area');
            alreadyBought = getCoords(y, x);
        }

        if (alreadyBought) {
            // This cell is already colored.
            uint8 soldTimes = lookup(req.owner, req.cell);

            require(
                soldTimes != 0,
                'Wrong address provided - cell ownership has changed'
            );

            if (msg.sender == req.owner) {
                // we own this cell
                // we only pay developer tax, cell resells is untouched.
                toDeveloper =
                    (getResellPrice(soldTimes) * resellTaxToDev) /
                    100;
                // We return the old resells without updating
                resells = soldTimes;
            } else {
                // Someone else owns this cell.
                // We must pay to the previous owner.
                if (soldTimes != 255) {
                    resells = soldTimes + 1;
                } else {
                    resells = soldTimes;
                }

                owner = req.owner;
                uint256 price = getResellPrice(soldTimes);

                toDeveloper = (price * resellTaxToDev) / 100;
                toOwner = price - toDeveloper;
            }
        } else {
            // This cell is not colored. Pay base price.
            toDeveloper += _prices[0];
        }

        return (toOwner, owner, toDeveloper, resells, alreadyBought);
    }
}

