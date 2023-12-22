//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

import "./Initializable.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./extensions_IERC20MetadataUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IRexbit.sol";
import "./IVestingWallet.sol";
import "./console.sol";

contract Vault is Initializable, OwnableUpgradeable {
    /// @dev rexbit token contract address
    IRexbit private _rxbToken;
    /// @dev vesting wallet contract address
    IVestingWallet private _vestingWallet;

    /// @dev payable tokens - USDT, USDC, BUSD
    mapping(address => bool) public payableTokens;
    /// @dev balances of USD tokens
    mapping(address => uint256) public balances;

    event TokenSold(
        address receiver,
        address usdToken,
        uint256 usdAmount,
        uint256 rxbAmount,
        uint256 soldTime
    );

    event Withdrawn(address usdToken, uint256 amount, uint256 time);

    modifier verifyToken(address usdToken) {
        require(payableTokens[usdToken], "Vault: unsupported payable token");
        _;
    }

    function initialize(
        address rxbAddress_,
        address vestingWallet_,
        address[] memory payableTokens_
    ) public initializer {
        __Ownable_init();
        _rxbToken = IRexbit(rxbAddress_);
        _vestingWallet = IVestingWallet(vestingWallet_);
        unchecked {
            for (uint256 i; i < payableTokens_.length; ) {
                payableTokens[payableTokens_[i]] = true;
                i++;
            }
        }
    }

    function privateBuy(
        address usdToken,
        uint256 usdAmount
    ) external verifyToken(usdToken) {
        require(usdAmount > 0, "Vault: USD Amount should not be 0");

        require(
            IERC20Upgradeable(usdToken).transferFrom(
                _msgSender(),
                address(this),
                usdAmount
            ),
            "Vault: USD Transfer Failed"
        );
        balances[usdToken] += usdAmount;

        uint256 rxbAmount = (usdAmount * 10 ** (_rxbToken.decimals() + 18)) /
            (10 ** IERC20MetadataUpgradeable(usdToken).decimals()) /
            _rxbToken.price(); // 18 is decimals of price

        _rxbToken.approve(address(_vestingWallet), rxbAmount);

        _vestingWallet.addVestingSchedule(_msgSender(), rxbAmount);

        emit TokenSold(
            _msgSender(),
            usdToken,
            usdAmount,
            rxbAmount,
            block.timestamp
        );
    }

    function approve(
        address to,
        address usdToken,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "Vault: amount is zero");
        IERC20Upgradeable(usdToken).approve(to, amount);
    }

    function withdraw(address usdToken, uint256 amount) external onlyOwner {
        require(amount > 0, "Vault: USD amount is zero");
        require(amount <= balances[usdToken], "Vault: Amount exceeds balance");

        if (IERC20Upgradeable(usdToken).transfer(owner(), amount)) {
            unchecked {
                balances[usdToken] -= amount;
            }

            emit Withdrawn(usdToken, amount, block.timestamp);
        }
    }

    function addPayableToken(
        address tokenAddress,
        string memory symbol
    ) external onlyOwner {
        require(
            compareStrings(
                IERC20MetadataUpgradeable(tokenAddress).symbol(),
                symbol
            ),
            "Vault: Symbol does not match"
        );
        payableTokens[tokenAddress] = true;
    }

    function removePayableToken(address tokenAddress) external onlyOwner {
        payableTokens[tokenAddress] = false;
    }

    function compareStrings(
        string memory a,
        string memory b
    ) public pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function transferByOwner(
        address advisor,
        uint256 amount
    ) external onlyOwner {
        _rxbToken.transfer(advisor, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

