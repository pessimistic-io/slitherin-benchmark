//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./ERC20Upgradeable.sol";
import "./AccessControlUpgradeable.sol";

import "./TokensRescuer.sol";

error IncorrectArray();
error IncorrectAmount();
error IncorrectBounds();
error IncorrectCategory();
error MaxSupplyExceeded();

contract Plx is ERC20Upgradeable, TokensRescuer, AccessControlUpgradeable {
    struct Category {
        uint32 start;
        uint32 end;
        uint256 tokenPerSec;
        uint256 minted;
        bytes32 minterRole;
    }

    mapping(uint256 => Category) public tokenomics;

    uint256 public constant maxTotalSupply = 100_000_000;

    bytes32 public constant BURNER_ROLE = bytes32("BURNER_ROLE");

    /**
     *  @notice Initializes the contract.
     *  @param name_ token name erc721
     *  @param symbol_ token symbol erc721
     */
    function __Plx_init(
        string memory name_,
        string memory symbol_,
        Category[] memory tokenomicsCategories
    ) external initializer {
        __ERC20_init_unchained(name_, symbol_);
        __Plx_init_unchained(tokenomicsCategories);
    }

    function mint(uint256 categoryId, address to) external {
        Category memory category = tokenomics[categoryId];

        if (category.tokenPerSec == 0) {
            revert IncorrectCategory();
        }

        _checkRole(category.minterRole);

        if (block.timestamp < category.end) {
            category.end = uint32(block.timestamp);
        }

        uint256 amount = (category.end - category.start) *
            category.tokenPerSec -
            category.minted;

        if (amount > 0) {
            tokenomics[categoryId].minted = category.minted + amount;

            _mint(to, amount);
        }
    }

    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    function getMaxSupplyByCategory(
        uint256 categoryId
    ) public view returns (uint256) {
        Category memory tokenomicsCategory = tokenomics[categoryId];

        return
            (tokenomicsCategory.end - tokenomicsCategory.start) *
            tokenomicsCategory.tokenPerSec;
    }

    /// @inheritdoc ITokensRescuer
    function rescueERC20Token(
        address token,
        uint256 amount,
        address receiver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _rescueERC20Token(token, amount, receiver);
    }

    /// @inheritdoc ITokensRescuer
    function rescueNativeToken(
        uint256 amount,
        address receiver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _rescueNativeToken(amount, receiver);
    }

    function __Plx_init_unchained(
        Category[] memory tokenomicsCategories
    ) internal onlyInitializing {
        if (tokenomicsCategories.length == 0) {
            revert IncorrectArray();
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        uint256 totalSupplyToCheck;
        for (uint256 i = 0; i < tokenomicsCategories.length; ++i) {
            Category memory tokenomicsCategory = tokenomicsCategories[i];

            if (tokenomicsCategory.start >= tokenomicsCategory.end) {
                revert IncorrectBounds();
            }

            if (tokenomicsCategory.tokenPerSec == 0) {
                revert IncorrectAmount();
            }

            tokenomics[i] = tokenomicsCategory;

            totalSupplyToCheck += getMaxSupplyByCategory(i);
        }

        if (totalSupplyToCheck > maxTotalSupply) {
            revert MaxSupplyExceeded();
        }
    }
}

