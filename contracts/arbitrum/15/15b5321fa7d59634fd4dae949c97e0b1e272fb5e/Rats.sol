// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";
import "./sd59x18_Math.sol";

// import "hardhat/console.sol";

import {UD60x18} from "./UD60x18.sol";

contract Rats is Ownable, ERC20 {
    address public immutable WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public immutable ETH = address(0);
    IVault public immutable BALANCER_VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IWeightedPoolFactory public immutable BALANCER_WEIGHTED_POOL_FACTORY =
        IWeightedPoolFactory(0xf1665E19bc105BE4EDD3739F88315cC699cc5b65);
    address public cheeseAddress;
    address public feesAddress;

    struct User {
        uint256 totalAmountBought;
        uint256 power;
        uint256 lastBoughtInEpoch;
        uint256 firstBoughtAt;
        uint256 totalAmountBoughtInCurrentEpoch;
    }

    mapping(address => User) public users;
    mapping(address => bool) public exempt;

    // uint256 public EPOCH_DURATION = 86400;
    uint256 public EPOCH_DURATION = 120;
    uint256 public TOTAL_FEE_BPS = 750;
    uint256 public DEV_FEE_BPS = 500;
    uint256 public LP_FEE_BPS = 250;
    uint256 public BPS = 10000;
    uint256 public MONTH = EPOCH_DURATION * 30;

    // BALANCE POOL
    IERC20[] tokens = new IERC20[](2);
    uint256 internal _ratsIndex = 0;
    uint256 internal _wethIndex = 1;
    bytes32 public poolId;

    uint256 public buyBonusPercentage = 1100000000000000000;

    uint256 public cheeseCanBeWithdrawnAt;

    event Bonus(address to, uint256 amount);
    event PowerIncreased(address from, uint256 power);
    event PowerWasted(address from, uint256 power);

    constructor(address feesAddress_) ERC20("tRATS", "tRATS") {
        feesAddress = feesAddress_;
        exempt[address(this)] = true;
        exempt[msg.sender] = true;
        _mint(address(this), 100000000 ether);
        cheeseCanBeWithdrawnAt = block.timestamp + MONTH;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        return _ratsTransfer(_msgSender(), recipient, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        return _ratsTransfer(from, to, amount);
    }

    function _ratsTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (exempt[sender] || exempt[recipient]) {
            _transfer(sender, recipient, amount);
            return true;
        }

        uint256 amountAfterFees;

        // BUY
        if (sender == address(BALANCER_VAULT)) {
            amountAfterFees = transferFeesAndReturnNewAmount(sender, amount);
            updateUser(recipient, amountAfterFees);

            User storage user = users[recipient];
            if (user.power != 0) {
                uint256 averageAmountBoughtInAllEpochs = user
                    .totalAmountBought / user.power;

                uint256 bonusableAmount = Math.min(
                    amount,
                    averageAmountBoughtInAllEpochs
                );

                uint256 bonus = calculateBuyBonus(bonusableAmount, user.power);

                _mint(recipient, bonus);
                emit Bonus(recipient, bonus);
            }
        } else {
            // Sell/transfer, reset everything

            emit PowerWasted(sender, users[sender].power);

            delete users[sender];

            // Sell, take fee
            if (recipient == address(BALANCER_VAULT)) {
                amountAfterFees = transferFeesAndReturnNewAmount(
                    sender,
                    amount
                );
            } else {
                amountAfterFees = amount;
                swapRatsToEthAndAddLiquidity();
            }
        }

        _transfer(sender, recipient, amountAfterFees);

        return true;
    }

    function updateUser(address address_, uint256 amount_) internal {
        User storage user = users[address_];

        if (user.firstBoughtAt == 0) {
            user.firstBoughtAt = block.timestamp;
        }

        uint256 currentUserEpoch = secondsToEpoch(
            block.timestamp - user.firstBoughtAt
        );

        if (user.lastBoughtInEpoch < currentUserEpoch) {
            user.power += 1;
            user.lastBoughtInEpoch = currentUserEpoch;
            user.totalAmountBought += user.totalAmountBoughtInCurrentEpoch;
            user.totalAmountBoughtInCurrentEpoch = 0;

            emit PowerIncreased(address_, user.power);
        }

        user.totalAmountBoughtInCurrentEpoch += amount_;
    }

    function transferFeesAndReturnNewAmount(
        address sender,
        uint256 amount
    ) internal returns (uint256) {
        uint256 newAmount = amount;
        uint256 feeAmount = calculateFeeAmount(amount);
        newAmount -= feeAmount;

        _transfer(sender, address(this), feeAmount);

        return newAmount;
    }

    function swapRatsToEthAndAddLiquidity() internal {
        uint256 totalRatsAmount = balanceOf(address(this));

        uint256 devRatsAmount = (totalRatsAmount * DEV_FEE_BPS) / TOTAL_FEE_BPS;
        uint256 lpRatsAmount = totalRatsAmount - devRatsAmount;

        swapRatsToEth(devRatsAmount);
        sendEth(feesAddress, address(this).balance);

        addLiquidity(lpRatsAmount);
    }

    function sendEth(address to, uint256 amount) internal {
        (bool sent, bytes memory data) = to.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function calculateBuyBonus(
        uint256 amount,
        uint256 power
    ) public view returns (uint256) {
        return
            UD60x18.unwrap(
                UD60x18
                    .wrap(amount)
                    .mul(UD60x18.wrap(buyBonusPercentage).powu(power))
                    .sub(UD60x18.wrap(amount))
            );
    }

    function calculateFeeAmount(uint256 amount) public view returns (uint256) {
        return (amount * TOTAL_FEE_BPS) / BPS;
    }

    function secondsToEpoch(uint256 seconds_) public view returns (uint256) {
        return (seconds_ / EPOCH_DURATION);
    }

    function createBalancerPool() external payable onlyOwner {
        require(cheeseAddress == address(0), "Pool already created");

        uint256[] memory weights = new uint256[](2);
        address[] memory assetManagers = new address[](2);

        if (address(this) > WETH) {
            _ratsIndex = 1;
            _wethIndex = 0;
        }

        tokens[_ratsIndex] = IERC20(address(this));
        tokens[_wethIndex] = IERC20(WETH);
        weights[_ratsIndex] = 950000000000000000;
        weights[_wethIndex] = 50000000000000000;

        assetManagers[0] = address(0);
        assetManagers[1] = address(0);

        cheeseAddress = BALANCER_WEIGHTED_POOL_FACTORY.create(
            "tCHEESE",
            "tCHEESE",
            tokens,
            weights,
            assetManagers,
            10000000000000000,
            address(this)
        );
        poolId = IBasePool(cheeseAddress).getPoolId();

        uint256[] memory amountsIn = new uint256[](2);

        tokens[_wethIndex] = IERC20(address(0));
        amountsIn[_ratsIndex] = balanceOf(address(this));
        amountsIn[_wethIndex] = msg.value;

        // Encode the userData for a multi-token join
        bytes memory userData = abi.encode(
            WeightedPoolUserData.JoinKind.INIT,
            amountsIn,
            0
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens),
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        _approve(
            address(this),
            address(BALANCER_VAULT),
            balanceOf(address(this))
        );

        BALANCER_VAULT.joinPool{value: msg.value}(
            poolId,
            address(this),
            address(this),
            request
        );
    }

    function withdrawCheese() public onlyOwner {
        require(
            block.timestamp >= cheeseCanBeWithdrawnAt,
            "Cannot withdraw cheese yet"
        );

        cheeseCanBeWithdrawnAt = block.timestamp + MONTH;

        uint256 amount = IERC20(cheeseAddress).balanceOf(address(this)) / 10; // 10% every month
        IERC20(cheeseAddress).transfer(msg.sender, amount);
    }

    function swapRatsToEth(uint256 ratsAmount) internal {
        _approve(address(this), address(BALANCER_VAULT), ratsAmount);

        IVault.FundManagement memory funds = IVault.FundManagement(
            address(this),
            false,
            payable(feesAddress),
            false
        );

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap(
            IBasePool(cheeseAddress).getPoolId(),
            IVault.SwapKind.GIVEN_IN,
            IAsset(address(this)),
            IAsset(ETH),
            ratsAmount,
            "0x"
        );

        BALANCER_VAULT.swap(singleSwap, funds, 1, block.timestamp);
    }

    function addLiquidity(uint256 ratsAmount) internal {
        _approve(address(this), address(BALANCER_VAULT), ratsAmount);
        uint256[] memory amountsIn = new uint256[](2);

        amountsIn[_ratsIndex] = ratsAmount;
        amountsIn[_wethIndex] = 0;

        // Encode the userData for a multi-token join
        bytes memory userData = abi.encode(
            WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsIn,
            0
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens),
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        BALANCER_VAULT.joinPool(poolId, address(this), address(this), request);
    }
}

interface IBasePool {
    function getPoolId() external view returns (bytes32);
}

interface IVault {
    function setRelayerApproval(
        address sender,
        address relayer,
        bool approved
    ) external;

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }
}

interface IWeightedPoolFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory weights,
        address[] memory assetManagers,
        uint256 swapFeePercentage,
        address owner
    ) external returns (address);
}

function _asIAsset(
    IERC20[] memory tokens
) pure returns (IAsset[] memory assets) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
        assets := tokens
    }
}

library VaultHelpers {
    /**
     * @dev Returns the address of a Pool's contract.
     *
     * This is the same code the Vault runs in `PoolRegistry._getPoolAddress`.
     */
    function toPoolAddress(bytes32 poolId) internal pure returns (address) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return address(uint160(uint256(poolId) >> (12 * 8)));
    }
}

library WeightedPoolUserData {
    // In order to preserve backwards compatibility, make sure new join and exit kinds are added at the end of the enum.
    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }
}

interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}

