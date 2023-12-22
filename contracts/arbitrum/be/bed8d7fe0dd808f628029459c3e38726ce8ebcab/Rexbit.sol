// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20Upgradeable.sol";

// import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract Rexbit is ERC20Upgradeable, PausableUpgradeable, OwnableUpgradeable {
    // Control support for EIP-2771 Meta Transactions
    bool public metaTxnsEnabled;

    // Private sale
    uint256 private _firstSupply;
    uint256 private _secondSupply;
    uint256 private _thirdSupply;

    uint256 private _mintStage; // sale stage 0 = first stage, 1 = second stage, 2 = third stage, 3 = general mint
    uint256 private _price;

    uint256 private _maxSupply;

    event MetaTxnsDisabled(address indexed caller);
    event MetaTxnsEnabled(address indexed caller);

    event PriceChanged(uint256 oldPrice, uint256 newPrice, uint256 time);
    event SaleStarted(uint8 stage, uint256 time);

    function initialize(uint256 price_) public initializer {
        __Ownable_init();
        __ERC20_init("REXBIT", "RXB");

        _firstSupply = 1000000 * 10 ** decimals(); // 1,000,000 RXB tokens in first stage
        _secondSupply = 1300000 * 10 ** decimals(); //  1,300,000 RXB tokens in second stage
        _thirdSupply = 1700000 * 10 ** decimals(); // 1,700,000 RXB tokens in third stage
        _maxSupply = 200000000 * 10 ** decimals(); // 200M tokens is maximum supply

        _price = price_;
    }

    // Disable support for meta transactions
    function disableMetaTxns() external onlyOwner {
        require(metaTxnsEnabled, "Rexbit: Meta trans disabled");

        metaTxnsEnabled = false;
        emit MetaTxnsDisabled(_msgSender());
    }

    // Enable support for meta transactions
    function enableMetaTxns() external onlyOwner {
        require(!metaTxnsEnabled, "Rexbit: Meta trans enabled");

        metaTxnsEnabled = true;
        emit MetaTxnsEnabled(_msgSender());
    }

    function firstSale(address to) external onlyOwner {
        require(_mintStage == 0, "Rexbit: First sale already done");

        _mint(to, _firstSupply);
        unchecked {
            _mintStage++;

            _mint(owner(), _maxSupply / 100);
        }

        emit SaleStarted(0, block.timestamp);
    }

    function secondSale(address to) external onlyOwner {
        require(_mintStage == 1, "Rexbit: Not second step");

        _mint(to, _secondSupply);
        unchecked {
            _mintStage++;
        }

        emit SaleStarted(1, block.timestamp);
    }

    function thirdSale(address to) external onlyOwner {
        require(_mintStage == 2, "Rexbit: Not third step");

        _mint(to, _thirdSupply);
        unchecked {
            _mintStage++;
        }

        emit SaleStarted(2, block.timestamp);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(_mintStage == 3, "Rexbit: Private sale not ended");

        require(
            totalSupply() + amount <= _maxSupply,
            "Rexbit: Max supply exceeded"
        );

        _mint(to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Returns the maximum amount of tokens that can be minted.
     */
    function maxSupply() external view returns (uint256) {
        return _maxSupply;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function updatePrice(uint256 newPrice) external onlyOwner {
        _price = newPrice;

        emit PriceChanged(_price, newPrice, block.timestamp);
    }

    /**
     * @dev return price of RXB token
     * @return USD per RXB token
     */
    function price() external view returns (uint256) {
        return _price;
    }

    function mintStage() external view returns (uint256) {
        return _mintStage;
    }
}

