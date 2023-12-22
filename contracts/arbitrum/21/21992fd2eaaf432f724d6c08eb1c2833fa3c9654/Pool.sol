// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./Initializable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./draft-IERC20PermitUpgradeable.sol";
import "./ERC165Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";

import "./IERC20X.sol";
import "./IPool.sol";
import "./Errors.sol";
import "./PriceConvertor.sol";
import "./PoolStorage.sol";
import "./ISyntheX.sol";
import "./IWETH.sol";

import "./PoolLogic.sol";
import "./CollateralLogic.sol";
import "./SynthLogic.sol";

/**
 * @title Pool
 * @notice Pool contract to manage collaterals and debt 
 * @author Prasad <prasad@chainscore.finance>
 */
contract Pool is 
    Initializable,
    IPool, 
    PoolStorage, 
    ERC20Upgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    UUPSUpgradeable
{
    /// @notice Using Math for uint256 to calculate minimum and maximum
    using MathUpgradeable for uint256;
    /// @notice Using SafeERC20 for IERC20 to prevent reverts
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice The address of the address storage contract
    /// @notice Stored here instead of PoolStorage to avoid Definition of base has to precede definition of derived contract
    ISyntheX public synthex;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /// @dev Initialize the contract
    function initialize(string memory _name, string memory _symbol, address _synthex, address weth) public initializer {
        __ERC20_init(_name, _symbol);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // check if valid address
        require(ISyntheX(_synthex).supportsInterface(type(ISyntheX).interfaceId), Errors.INVALID_ADDRESS);
        // set addresses
        synthex = ISyntheX(_synthex);

        WETH_ADDRESS = weth;
        
        // paused till (1) collaterals are added, (2) synths are added and (3) feeToken is set
        _pause();
    }

    ///@notice required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyL1Admin {}

    // Support IPool interface
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IPool).interfaceId;
    }

    /// @dev Override to disable transfer
    function _transfer(address, address, uint256) internal virtual override {
        revert(Errors.TRANSFER_FAILED);
    }

    /* -------------------------------------------------------------------------- */
    /*                              External Functions                            */
    /* -------------------------------------------------------------------------- */
    receive() external payable {}
    fallback() external payable {}

    /**
     * @notice Enable a collateral
     * @param _collateral The address of the collateral
     */
    function enterCollateral(address _collateral) virtual override public {
        CollateralLogic.enterCollateral(
            _collateral,
            collaterals,
            accountMembership,
            accountCollaterals
        );
    }

    /**
     * @notice Exit a collateral
     * @param _collateral The address of the collateral
     */
    function exitCollateral(address _collateral) virtual override public {
        CollateralLogic.exitCollateral(
            _collateral,
            accountMembership,
            accountCollaterals
        );
        require(getAccountLiquidity(msg.sender).liquidity >= 0, Errors.INSUFFICIENT_COLLATERAL);
    }

    /**
     * @notice Deposit ETH
     */
    function depositETH(address _account) virtual override public payable {
        CollateralLogic.depositETH(
            _account, 
            WETH_ADDRESS, 
            msg.value, 
            collaterals, 
            accountMembership, 
            accountCollateralBalance, 
            accountCollaterals
        );
    }

    /**
     * @notice Deposit collateral
     * @param _collateral The address of the erc20 collateral
     * @param _amount The amount of collateral to deposit
     * @param _approval The amount of collateral to approve
     */
    function depositWithPermit(
        address _collateral, 
        uint _amount,
        address _account,
        uint _approval, 
        uint _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) virtual override public whenNotPaused {
        CollateralLogic.depositWithPermit(
            _account, 
            _collateral, 
            _amount, 
            _approval, 
            _deadline, 
            _v, 
            _r, 
            _s, 
            collaterals, 
            accountMembership, 
            accountCollateralBalance, 
            accountCollaterals
        );
    }

    /**
     * @notice Deposit collateral
     * @param _collateral The address of the erc20 collateral
     * @param _amount The amount of collateral to deposit
     */
    function deposit(address _collateral, uint _amount, address _account) virtual override public whenNotPaused {
        CollateralLogic.depositERC20(
            _account, 
            _collateral, 
            _amount, 
            collaterals, 
            accountMembership, 
            accountCollateralBalance, 
            accountCollaterals
        );
    }

    /**
     * @notice Withdraw collateral
     * @param _collateral The address of the collateral
     * @param _amount The amount of collateral to withdraw
     */
    function withdraw(address _collateral, uint _amount, bool unwrap) virtual override public {
        // Process withdrawal
        CollateralLogic.withdraw(
            _collateral, 
            _amount, 
            collaterals,
            accountCollateralBalance
        );
        require(getAccountLiquidity(msg.sender).liquidity >= 0, Errors.INSUFFICIENT_COLLATERAL);
        // Transfer collateral to user
        transferOut(_collateral, msg.sender, _amount, unwrap);
    }

    /**
     * @notice Transfer asset out to address
     * @param _asset The address of the asset
     * @param recipient The address of the recipient
     * @param _amount Amount
     */
    function transferOut(address _asset, address recipient, uint _amount, bool unwrap) internal nonReentrant {
        if(_asset == WETH_ADDRESS && unwrap){
            IWETH(WETH_ADDRESS).withdraw(_amount);
            (bool success, ) = recipient.call{value: _amount}("");
            require(success, Errors.TRANSFER_FAILED);
        } else {
            IERC20Upgradeable(_asset).safeTransfer(recipient, _amount);
        }
    }

    /**
     * @notice Issue synths to the user
     * @param _synthIn The address of the synth
     * @param _amountIn Amount of synth
     * @dev Only Active Synth (ERC20X) contract can be issued
     */
    function mint(address _synthIn, uint _amountIn, address _to) virtual override whenNotPaused external returns(uint mintAmount) {
        mintAmount = SynthLogic.commitMint(
            SynthLogic.MintVars(
                _to,
                _amountIn, 
                priceOracle, 
                _synthIn, 
                feeToken, 
                balanceOf(msg.sender),
                totalSupply(),
                getTotalDebtUSD(),
                getAccountLiquidity(msg.sender),
                issuerAlloc,
                synthex
            ),
            synths
        );
        // Mint debt to sender
        _mint(msg.sender, mintAmount);
    }

    /**
     * @notice Burn synths from the user
     * @param _synthIn User whose debt is being burned
     * @param _amountIn The amount of synths to burn
     * @return burnAmount The amount of synth burned
     * @notice The amount of synths to burn is calculated based on the amount of debt tokens burned
     * @dev Only Active/Disabled Synth (ERC20X) contract can call this function
     */
    function burn(address _synthIn, uint _amountIn) virtual override whenNotPaused external returns(uint burnAmount) {
        burnAmount = SynthLogic.commitBurn(
            SynthLogic.BurnVars(
                _amountIn, 
                priceOracle, 
                _synthIn, 
                feeToken, 
                balanceOf(msg.sender),
                totalSupply(),
                getUserDebtUSD(msg.sender),
                getTotalDebtUSD(),
                issuerAlloc,
                synthex
            ),
            synths
        );
        
        _burn(msg.sender, burnAmount);
    }

    /**
     * @notice Exchange a synthetic asset for another
     * @param _synthIn The address of the synthetic asset to exchange
     * @param _amount The amount of synthetic asset to exchangs
     * @param _synthOut The address of the synthetic asset to receive
     * @param _kind The type of exchange to perform
     * @dev Only Active/Disabled Synth (ERC20X) contract can call this function
     */
    function swap(address _synthIn, uint _amount, address _synthOut, DataTypes.SwapKind _kind, address _to) virtual override whenNotPaused external returns(uint[2] memory) {
        return SynthLogic.commitSwap(
            SynthLogic.SwapVars(
                _to,
                _synthIn,
                _synthOut,
                _amount, 
                _kind,
                priceOracle,
                feeToken,
                issuerAlloc,
                synthex
            ),
            synths
        );
    }

    /**
     * @notice Liquidate a user's debt
     * @param _synthIn The address of the liquidator
     * @param _account The address of the account to liquidate
     * @param _amount The amount of debt (in repaying synth) to liquidate
     * @param _outAsset The address of the collateral asset to receive
     * @dev Only Active/Disabled Synth (ERC20X) contract can call this function
     */
    function liquidate(address _synthIn, address _account, uint _amount, address _outAsset) virtual override whenNotPaused external {
        require(accountMembership[_outAsset][_account], Errors.ACCOUNT_NOT_ENTERED);
        (uint refundOut, uint burnAmount) = SynthLogic.commitLiquidate(
            SynthLogic.LiquidateVars(
                _amount, 
                _account,
                priceOracle, 
                _synthIn, 
                _outAsset,
                feeToken,
                totalSupply(),
                getTotalDebtUSD(),
                getAccountLiquidity(_account),
                issuerAlloc,
                synthex
            ),
            accountCollateralBalance,
            synths,
            collaterals
        );
        // Transfer refund to user
        if(refundOut > 0){
            transferOut(_outAsset, _account, refundOut, false);
        }
        // Burn debt
        _burn(_account, burnAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                               View Functions                               */
    /* -------------------------------------------------------------------------- */
    /**
     * @dev Get the total adjusted position of an account: E(amount of an asset)*(volatility ratio of the asset)
     * @param _account The address of the account
     * @return liq liquidity The total debt of the account
     */
    function getAccountLiquidity(address _account) virtual override public view returns(DataTypes.AccountLiquidity memory liq) {
        return PoolLogic.accountLiquidity(priceOracle, accountCollaterals[_account], accountCollateralBalance[_account], collaterals, getUserDebtUSD(_account));
    }

    /**
     * @dev Get the total debt of a trading pool
     * @return totalDebt The total debt of the trading pool
     */
    function getTotalDebtUSD() virtual override public view returns(uint totalDebt) {
        return PoolLogic.totalDebtUSD(synthsList, priceOracle);
    }

    /**
     * @dev Get the debt of an account in this trading pool
     * @param _account The address of the account
     * @return The debt of the account in this trading pool
     */
    function getUserDebtUSD(address _account) virtual override public view returns(uint){
        return PoolLogic.userDebtUSD(
            totalSupply(),
            balanceOf(_account),
            getTotalDebtUSD()
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                               Admin Functions                              */
    /* -------------------------------------------------------------------------- */

    modifier onlyL1Admin() {
        require(synthex.isL1Admin(msg.sender), Errors.CALLER_NOT_L1_ADMIN);
        _;
    }

    modifier onlyL2Admin() {
        require(synthex.isL2Admin(msg.sender), Errors.CALLER_NOT_L2_ADMIN);
        _;
    }

    /**
     * @notice Pause the contract 
     * @dev Only callable by L2 admin
     */
    function pause() public onlyL2Admin {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only callable by L2 admin
     */
    function unpause() public onlyL2Admin {
        _unpause();
    }

    /**
     * @notice Set the price oracle
     * @param _priceOracle The address of the price oracle
     * @dev Only callable by L1 admin
     */
    function setPriceOracle(address _priceOracle) external onlyL1Admin {
        require(_priceOracle != address(0), Errors.INVALID_ARGUMENT);
        priceOracle = IPriceOracle(_priceOracle);
        require(priceOracle.getAssetPrice(feeToken) > 0, Errors.INVALID_ADDRESS);
        emit PriceOracleUpdated(_priceOracle);
    }

    function setIssuerAlloc(uint _issuerAlloc) external onlyL1Admin {
        require(issuerAlloc <= BASIS_POINTS, Errors.INVALID_ARGUMENT);
        issuerAlloc = _issuerAlloc;
        emit IssuerAllocUpdated(_issuerAlloc);
    }

    function setFeeToken(address _feeToken) external onlyL1Admin {
        require(_feeToken != address(0), Errors.INVALID_ARGUMENT);
        require(_feeToken != feeToken, Errors.ALREADY_SET);
        require(synths[_feeToken].isActive, Errors.ASSET_NOT_ACTIVE);
        feeToken = _feeToken;
        emit FeeTokenUpdated(_feeToken);
    }
    
    /**
     * @notice Update collateral params
     * @notice Only L1Admin can call this function 
     */
    function updateCollateral(address _collateral, DataTypes.Collateral memory _params) virtual override public onlyL1Admin {
        PoolLogic.update(collaterals, _collateral, _params);
    }

    /**
     * @dev Add a new synth to the pool
     * @notice Only L1Admin can call this function
     */
    function addSynth(address _synth, DataTypes.Synth memory _params) external override onlyL1Admin {
        PoolLogic.add(synths, synthsList, _synth, _params);
    }

    /**
     * @dev Update synth params
     * @notice Only L1Admin can call this function
     */
    function updateSynth(address _synth, DataTypes.Synth memory _params) virtual override public onlyL1Admin {
        PoolLogic.update(synths, _synth, _params);
    }

    /**
     * @dev Removes the synth from the pool
     * @param _synth The address of the synth to remove
     * @notice Removes from synthList => would not contribute to pool debt
     * @notice Only L1Admin can call this function
     */
    function removeSynth(address _synth) virtual override public onlyL1Admin {
        PoolLogic.remove(synths, synthsList, _synth);
    }
}
