// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./SafeMath.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";

import "./INUON.sol";
import "./INLP.sol";
import "./INUONController.sol";
import "./ITruflation.sol";
import "./IERC20Burnable.sol";

interface IUniswapPairOracle {
    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);
}

interface IChainlinkOracle {
    function latestAnswer() external view returns (uint256);
}

interface IUniswapRouterETH {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IRelayer {
    function depositOnVault(uint256 _amount) external returns(uint256);
    function withdrawFromVault(uint256 _shares) external returns (uint256);
    function getPPFS() external view returns (uint256);
}

/**
* @notice The Collateral Hub (CHub) is receiving collaterals from users, and mint them back NUON according to the collateral ratio defined in the NUON Controller
* @dev (Driiip) TheHashM
* @author This Chub is designed by Gniar & TheHashM 
*/
contract CollateralHubUSDC is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;

    /**
    * @dev Contract instances.
    */
    address private NUONController;
    address private Treasury;
    address private NUON;
    address private NuonOracleAddress;
    address private ChainlinkOracle;
    address private TruflationOracle;
    address private collateralUsed;
    address private unirouter;
    address private lpPair;
    address private NLP;
    address private Relayer;

    /**
    * @notice Contract Data : mapping and infos
    */
    mapping(uint256 => bool) private vaultsRedeemPaused;
    mapping(address => uint256) private usersIndex;
    mapping(address => uint256) private usersAmounts;
    mapping(address => uint256) private mintedAmount;
    mapping(address => uint256) private userLPs;
    mapping(address => bool) private nlpCheck;
    mapping(address => uint256) private nlpPerUser;

    address[] public users;
    address[] private collateralToNuonRoute;
    uint256 private liquidationFee;
    uint256 private minimumDepositAmount;
    uint256 private liquidityBuffer;
    uint256 private liquidityCheck;
    uint256 private maxNuonBurnPercent;
    uint256 private constant MAX_INT = 2**256 - 1;
    uint256 private assetMultiplier;
    uint256 private decimalDivisor;
    uint256 private count;

    /**
     * @notice Events.
     */
    event MintedNUON(address indexed user, uint256 NUONAmountD18, uint256 NuonPrice, uint256 collateralAmount);
    event Redeemed(address indexed user, uint256 fullAmount, uint256 NuonAmount);
    event depositedWithoutMint(address indexed user, uint256 fees, uint256 depositedAmount);
    event mintedWithoutDeposit(address indexed user, uint256 mintedAmount, uint256 collateralRequired);
    event redeemedWithoutNuon(address indexed user, uint256 fees, uint256 amountSentToUser);
    event burnedNuon(address indexed user, uint256 burnedAmount, uint256 LPSent);

    /**
    * @dev We deploy using initialize with openzeppelin/truffle-upgrades
    * @notice No 0 addresses allowed
    */
    function initialize(
        address _NUON,
        address _NUONController,
        address _treasury,
        address _truflationOracle,
        address _collateralUsed,
        address _ChainlinkOracle,
        uint256 _assetMultiplier,
        uint256 _liquidationFee,
        uint256 _decimalDivisor
    ) public initializer {

        NUON = _NUON;
        NUONController = _NUONController;
        Treasury = _treasury;
        TruflationOracle = _truflationOracle;
        collateralUsed = _collateralUsed;
        assetMultiplier = _assetMultiplier;
        ChainlinkOracle = _ChainlinkOracle;
        collateralToNuonRoute = [collateralUsed,NUON];
        liquidationFee = _liquidationFee;
        decimalDivisor = _decimalDivisor;
        count ++;
        __Ownable_init();
    }

    /**
     * @notice Sets the core addresses used by the contract
     * @param _treasury Treasury contract
     * @param _controller NUON controller
     */
    function setCoreAddresses(
        address _treasury,
        address _controller,
        address _router,
        address _lpPair,
        address[] memory _collateralToNuonRoute,
        address _NLP,
        address _Relayer,
        address _nuonOracle,
        address _truflation,
        address _ChainlinkOracle
    ) public onlyOwner {
        Treasury = _treasury;
        NUONController = _controller;
        unirouter = _router;
        lpPair = _lpPair;
        collateralToNuonRoute = _collateralToNuonRoute;
        NLP = _NLP;
        Relayer = _Relayer;
        NuonOracleAddress = _nuonOracle;
        TruflationOracle = _truflation;
        ChainlinkOracle = _ChainlinkOracle;
    }

    function setLiquidityParams(
        uint256 _liquidityCheck,
        uint256 _liquidityBuffer,
        uint256 _maxNuonBurnPercent,
        uint256 _minimumDepositAmount) public onlyOwner {
        require(_liquidityCheck != 0 && _liquidityBuffer != 0 && _minimumDepositAmount > 0, "Need to be above 0");
        require(_liquidityCheck <= 150e18 && _liquidityBuffer <= 50 && _maxNuonBurnPercent <= 99 , "Need to be below the limit");
        liquidityCheck = _liquidityCheck;
        liquidityBuffer = _liquidityBuffer;
        maxNuonBurnPercent = _maxNuonBurnPercent;
        minimumDepositAmount = _minimumDepositAmount;
    }
    
    /**
     * @notice A series of view functions to return the contract status.For front end peeps.
     */

    function getAllUsers() public view returns (address[] memory) {
        return users;
    }

    function getPositionOwned(address _owner) public view returns (uint256) {
        return nlpPerUser[_owner];
    }

    function viewUserCollateralAmount(address _user) public view returns (uint256) {
        return (usersAmounts[_user]);
    }

    function viewUserMintedAmount(address _user) public view returns (uint256) {
        return (mintedAmount[_user]);
    }

    function viewUserVaultSharesAmount(address _user) public view returns (uint256) {
        return (userLPs[_user]);
    }

    function getNUONPrice()
        public
        view
        returns (uint256)
    {
        uint256 assetPrice;
        if (NuonOracleAddress == address(0)) {
            assetPrice = 1e18;
        } else {
            assetPrice = IUniswapPairOracle(NuonOracleAddress).consult(NUON,1e18);
        }
        return assetPrice;
    }

    function getUserCollateralRatioInPercent(address _user)
        public
        view
        returns (uint256)
    {
        if (viewUserCollateralAmount(_user) > 0) {
            uint256 userTVL = (viewUserCollateralAmount(_user) * assetMultiplier) * getCollateralPrice() / 1e18;
            uint256 mintedValue = viewUserMintedAmount(_user) * getNUONPrice() / 1e18;
            return (userTVL * 1e18) / mintedValue * 100;
        } else {
            return 0;
        }

    }

    function getUserLiquidationStatus(address _user) public view returns (bool) {
        uint256 ratio = INUONController(NUONController).getGlobalCollateralRatio(address(this));
        if (collateralPercentToRatio(_user) > ratio) {
            return true;
        } else {
            return false;
        }
    }

    function collateralPercentToRatio(address _user)
        public
        view
        returns (uint256)
    {
        uint256 rat = 1e18 * 1e18 / getUserCollateralRatioInPercent(_user) * 100;
        return rat;
    }

    /**
     * @notice A view function to estimate the amount of NUON out. For front end peeps.
     * @param collateralAmount The amount of collateral that the user wants to use
     * return The NUON amount to be minted, the minting fee in d18 format, and the collateral to be deposited after the fees have been taken
     */
    function estimateMintedNUONAmount(uint256 collateralAmount, uint256 _collateralRatio)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        require(_collateralRatio <= INUONController(NUONController).getGlobalCollateralRatio(address(this)),"Collateral Ratio out of bounds");
        require(_collateralRatio >= INUONController(NUONController).getMaxCratio(address(this)),"Collateral Ratio too low");
        require(collateralAmount > minimumDepositAmount, "Please deposit more than the min required amount");

        uint256 collateralAmountAfterFees = collateralAmount.sub(
        collateralAmount.mul(INUONController(NUONController).getMintingFee(address(this)))
        .div(100)
        .div(1e18));

        uint256 collateralAmountAfterFeesD18 = collateralAmountAfterFees *
            assetMultiplier;

        uint256 NUONAmountD18;

        NUONAmountD18 = calcOverCollateralizedMintAmounts(
                _collateralRatio,
                getCollateralPrice(),
                collateralAmountAfterFeesD18
            );

        (uint256 collateralRequired,)= mintLiquidityHelper(NUONAmountD18);
        return (
                NUONAmountD18,
                INUONController(NUONController).getMintingFee(address(this)),
                collateralAmountAfterFees,
                collateralRequired
            );
    }

    /**
     * @notice A view function to get the collateral price of an asset directly on chain
     * return The asset price
     */
    function getCollateralPrice()
        public
        view
        returns (uint256)
    {
            uint256 assetPrice = IChainlinkOracle(ChainlinkOracle).latestAnswer().mul(1e10);
            return assetPrice;
    }

    /**
     * @notice A view function to estimate the collaterals out after NUON redeem. For end end peeps.
     * @param _user A specific user
     * @param NUONAmount The NUON amount to give back to the collateral hub.
     * return The collateral amount out, the NUON burned in the process, and the fees taken by the ecosystem
     */
    function estimateCollateralsOut(
        address _user,
        uint256 NUONAmount
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 userAmount = usersAmounts[_user];
        uint256 userMintedAmount = mintedAmount[_user];
        
        require(userAmount > 0, 'You do not have any balance in that CHUB');

        uint256 fullAmount = calcOverCollateralizedRedeemAmounts(
            collateralPercentToRatio(_user),
            getCollateralPrice(),
            NUONAmount,
            assetMultiplier
        ).div(decimalDivisor);

        require(NUONAmount <= userMintedAmount, 'Not enough NUON to burn');
        if (NUONAmount == mintedAmount[msg.sender] || fullAmount >= userAmount) {
             fullAmount = userAmount;
        }

        uint256 fees = fullAmount
            .mul(INUONController(NUONController).getRedeemFee(address(this)))
            .div(100)
            .div(1e18);
        uint256 collateralFees = fullAmount.sub(fees);

        return (fullAmount, collateralFees, fees);
    }

    /**
     * @notice Used to mint NUON as a user deposit collaterals
     * return The minted NUON amount
     * @dev collateralAmount is in USDT
     */
    function mint(
        uint256 _collateralRatio,
        uint256 _amount
    )
        external
        nonReentrant
        returns (uint256)
    {
        require(
            INUONController(NUONController).isMintPaused() == false,
            'CHUB: Minting paused! Aaah!'
        );

        //cratio has to be bigger than the minimum required in the controller, otherwise user can get liquidated instantly
        //It has to be lower because lower means higher % cratio
        require(_collateralRatio <= INUONController(NUONController).getGlobalCollateralRatio(address(this)),"Collateral Ratio out of bounds");
        require(_collateralRatio >= INUONController(NUONController).getMaxCratio(address(this)),"Collateral Ratio too low");

        if (usersAmounts[msg.sender] == 0) {
            usersIndex[msg.sender] = users.length;
            users.push(msg.sender);
            if (msg.sender != owner()) {
                require(nlpCheck[msg.sender] == false, "You already have a position");
                //just used to increment new NFT IDs
                uint256 newItemId = count;
                count ++;
                INLP(NLP).mintNLP(msg.sender, newItemId);
                INLP(NLP)._createPosition(msg.sender,newItemId);
                nlpCheck[msg.sender] = true;
                nlpPerUser[msg.sender] = newItemId;
            }
        }
        //In case the above if statement isnt executed we need to instantiate the
        //storage element here to update the position status
        uint256 collateralAmount = _amount;
        require(collateralAmount > minimumDepositAmount, "Please deposit more than the min required amount");

        (uint256 NUONAmountD18,
        ,
        uint256 collateralAmountAfterFees,
        uint256 collateralRequired)  = estimateMintedNUONAmount(collateralAmount, _collateralRatio);
        uint256 userAmount = usersAmounts[msg.sender];
        usersAmounts[msg.sender] = userAmount.add(collateralAmountAfterFees);
        mintedAmount[msg.sender] = mintedAmount[msg.sender].add(NUONAmountD18);

        if (msg.sender != owner()) {
            IERC20Burnable(collateralUsed).transferFrom(msg.sender, address(this),_amount.add(collateralRequired));
            _addLiquidity(collateralRequired);
            INLP(NLP)._addAmountToPosition(mintedAmount[msg.sender], usersAmounts[msg.sender], userLPs[msg.sender], nlpPerUser[msg.sender]);
        } else {
            IERC20Burnable(collateralUsed).transferFrom(msg.sender, address(this),_amount);
        }
        
        IERC20Burnable(collateralUsed).transfer(
            Treasury,
            collateralAmount.sub(collateralAmountAfterFees)
        );
        INUON(NUON).mint(msg.sender, NUONAmountD18);
        emit MintedNUON(msg.sender, NUONAmountD18,getNUONPrice(),collateralAmount);
        return NUONAmountD18;
    }

    function addLiquidityForUser(uint256 _amount) public nonReentrant {
        require(usersAmounts[msg.sender] > 0, "You do not have a position in the CHUB");
        IERC20Burnable(collateralUsed).transferFrom(msg.sender, address(this),_amount);
        _addLiquidity(_amount);
    }

    function removeLiquidityForUser(uint256 _amount) public nonReentrant {
        require(usersAmounts[msg.sender] > 0, "You do not have a position in the CHUB");
        uint256 sharesAmount = userLPs[msg.sender];
        uint256 mintedValue = viewUserMintedAmount(msg.sender);
        require(sharesAmount >= _amount,"Cannot remove more than your full Balance");
        userLPs[msg.sender] = userLPs[msg.sender].sub(_amount);
        uint256 lpToSend = _removeUserLPs(_amount);
        require(getUserLiquidityCoverage(msg.sender,0) > liquidityCheck, "This will affect your liquidity coverage");
        IERC20Burnable(lpPair).transfer(msg.sender, lpToSend);
    }

    function _addLiquidity(uint256 _amount) internal {
        address router = unirouter;
        uint256 _amountDiv2 = _amount.div(2);
        IERC20Burnable(collateralUsed).approve(router, _amount);

        uint256 balBefore = IERC20Burnable(NUON).balanceOf(address(this));
        IUniswapRouterETH(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountDiv2,
                0,
                collateralToNuonRoute,
                address(this),
                block.timestamp
        );
        uint256 balAfter = IERC20Burnable(NUON).balanceOf(address(this));
        IERC20Burnable(NUON).approve(router, balAfter.sub(balBefore));

        uint256 balOfLPBefore = IERC20Burnable(lpPair).balanceOf(address(this));
        IUniswapRouterETH(router).addLiquidity(
            NUON,
            collateralUsed,
            balAfter.sub(balBefore),
            _amountDiv2,
            0,
            0,
            address(this),
            block.timestamp
        );
        uint256 balOfLPAfter = IERC20Burnable(lpPair).balanceOf(address(this));
        
        IERC20Burnable(lpPair).approve(Relayer, balOfLPAfter.sub(balOfLPBefore));
        uint256 shares = IRelayer(Relayer).depositOnVault(balOfLPAfter.sub(balOfLPBefore));
        userLPs[msg.sender] = userLPs[msg.sender].add(shares);
    }

    function _removeUserLPs(uint256 _shares) internal returns (uint256) {
        uint256 LPReceived = IRelayer(Relayer).withdrawFromVault(_shares);
        return(LPReceived);
    }

    /**
     * @notice Used to redeem a collateral amount as a user gives back NUON
     * @param NUONAmount NUON amount to give back
     * @dev NUONAmount is always in d18, use estimateCollateralsOut() to estimate the amount of collaterals returned
     * Users from the market cannot redeem collaterals. Only minters.
     */
    function redeem(uint256 NUONAmount)
        external
        nonReentrant
    {
        
        require(
            INUONController(NUONController).isRedeemPaused() == false,
            'CHUB: Minting paused! Aaah!'
        );
        // Check is user should be liquidated
        if (getUserLiquidationStatus(msg.sender)) {
            liquidateUserAssets(msg.sender);
        } else {

        uint256 userAmount = usersAmounts[msg.sender];
        (uint256 fullAmount,uint256 fullAmountSubFees,uint256 fees) = estimateCollateralsOut(msg.sender,NUONAmount);

        if (NUONAmount == mintedAmount[msg.sender] || fullAmount >= userAmount) {
            fullAmount = userAmount;

            if (msg.sender != owner()) {
                uint256 usernlp = nlpPerUser[msg.sender];
                uint256 sharesAmount = userLPs[msg.sender];
                INLP(NLP).burnNLP(usernlp);
                INLP(NLP)._deletePositionInfo(msg.sender);
                _deleteUsersData(msg.sender);
                uint256 lpToSend = _removeUserLPs(sharesAmount);
                IERC20Burnable(lpPair).transfer(msg.sender, lpToSend);
            }
            mintedAmount[msg.sender] = 0;
            usersAmounts[msg.sender] = 0;
            delete users[usersIndex[msg.sender]];
            usersIndex[msg.sender] = 0;
        } else {
            require(fullAmount <= userAmount, 'Not enough balance');
            mintedAmount[msg.sender] = mintedAmount[msg.sender].sub(
            NUONAmount
            );
            usersAmounts[msg.sender] = userAmount.sub(fullAmount);
            if (msg.sender != owner()) {
                INLP(NLP)._addAmountToPosition(mintedAmount[msg.sender], usersAmounts[msg.sender], userLPs[msg.sender], nlpPerUser[msg.sender]);
            }
        }

        INUON(NUON).transferFrom(msg.sender, address(this), NUONAmount);
        IERC20Burnable(NUON).burn(NUONAmount);
        
        IERC20Burnable(collateralUsed).transfer(msg.sender, fullAmountSubFees);
        IERC20Burnable(collateralUsed).transfer(Treasury,fees);

        emit Redeemed(msg.sender, fullAmount, NUONAmount);

        }
    }

    function depositWithoutMint(
        uint256 _amount
    )
        external
        nonReentrant
    {
        require(
            INUONController(NUONController).isMintPaused() == false,
            'CHUB: Minting paused! Aaah!'
        );

        uint256 collateralAmount = _amount;
        require(collateralAmount > minimumDepositAmount, "Please deposit more than the min required amount");

        uint256 userAmount = usersAmounts[msg.sender];
        uint256 collateralAmountAfterFees = collateralAmount.sub(
        collateralAmount.mul(INUONController(NUONController).getMintingFee(address(this)))
        .div(100)
        .div(1e18));

        usersAmounts[msg.sender] = userAmount.add(collateralAmountAfterFees);

        if(getUserLiquidationStatus(msg.sender)) {
            revert("This will liquidate you");
        } else {
            IERC20Burnable(collateralUsed).transferFrom(msg.sender, address(this),_amount);
            INLP(NLP)._addAmountToPosition(mintedAmount[msg.sender], usersAmounts[msg.sender], userLPs[msg.sender], nlpPerUser[msg.sender]);
            IERC20Burnable(collateralUsed).transfer(
            Treasury,
            collateralAmount.sub(collateralAmountAfterFees));
            require(collateralPercentToRatio(msg.sender) >= INUONController(NUONController).getMaxCratio(address(this)),"Collateral Ratio too low");
            emit depositedWithoutMint(msg.sender, collateralAmount.sub(collateralAmountAfterFees),collateralAmountAfterFees);
        }
    }

    function _depositWithoutMintEstimation(
        uint256 _amount,
        address _user
    )
        public
        view
        returns(uint256,uint256,uint256)
    {

        require(_amount > minimumDepositAmount, "Please deposit more than the min required amount");
        uint256 collateralAmountAfterFees = _amount.sub(
        _amount.mul(INUONController(NUONController).getMintingFee(address(this)))
        .div(100)
        .div(1e18));

        uint256 ratio = INUONController(NUONController).getGlobalCollateralRatio(address(this));
        if (viewUserCollateralAmount(_user) > 0) {
            uint256 userTVL = ((viewUserCollateralAmount(_user).add(_amount)) * assetMultiplier) * getCollateralPrice() / 1e18;
            uint256 totalNUON = viewUserMintedAmount(_user);
            uint256 mintedValue =  totalNUON * getNUONPrice() / 1e18;
            uint256 result =  (userTVL * 1e18) / mintedValue * 100;
            uint256 rat = 1e18 * 1e18 / result * 100;
            require(rat < ratio, "This will liquidate you");
            return (result, collateralAmountAfterFees,userTVL);
        } else {
            return (0,0,0);
        }
    }

    /**
     * @notice Used to mint NUON without depositing collaterals, user has to have a position in the CHUB already
     * liquidations are automatic if user is over the threshold
     * return The minted NUON amount
     * @dev collateralAmount is in WETH
     */
    function mintWithoutDeposit(
        uint256 _amount
    )
        external
        nonReentrant
        returns (uint256)
    {
        require(
            INUONController(NUONController).isMintPaused() == false,
            'CHUB: Minting paused! Aaah!'
        );

        //cratio has to be bigger than the minimum required in the controller, otherwise user can get liquidated instantly
        //lower value means higher cratio
        require(usersAmounts[msg.sender] > 0, "You do not have a position in the CHUB");
        uint256 amountToMint = _amount;
        uint256 collateralRequired;

        mintedAmount[msg.sender] = mintedAmount[msg.sender].add(amountToMint);
        INLP(NLP)._addAmountToPosition(mintedAmount[msg.sender], usersAmounts[msg.sender], userLPs[msg.sender], nlpPerUser[msg.sender]);

        if (getUserLiquidityCoverage(msg.sender,0) < liquidityCheck) {
            (collateralRequired,)= mintLiquidityHelper(_amount);
            IERC20Burnable(collateralUsed).transferFrom(msg.sender, address(this),collateralRequired);
            _addLiquidity(collateralRequired);
        }

        if(getUserLiquidationStatus(msg.sender)) {
            revert("This will liquidate you");
        } else {
            INUON(NUON).mint(msg.sender, amountToMint);
            emit mintedWithoutDeposit(msg.sender, amountToMint,collateralRequired);
        }

        return amountToMint;
    }

    function _mintWithoutDepositEstimation(
        uint256 _amount,
        address _user
    )
        public
        view
        returns (uint256,uint256,uint256,uint256)
    {
        uint256 ratio = INUONController(NUONController).getGlobalCollateralRatio(address(this));
        require(usersAmounts[_user] > 0, "You do not have a position in the CHUB");
        if (viewUserCollateralAmount(_user) > 0) {
            uint256 userTVL = (viewUserCollateralAmount(_user) * assetMultiplier) * getCollateralPrice() / 1e18;
            uint256 totalNUON = viewUserMintedAmount(_user).add(_amount);
            uint256 mintedValue =  totalNUON * getNUONPrice() / 1e18;
            uint256 result =  (userTVL * 1e18) / mintedValue * 100;
            uint256 rat = 1e18 * 1e18 / result * 100;
            (uint256 collateralRequired,)= mintLiquidityHelper(_amount);

            require(rat < ratio, "This will liquidate you");
            return (result, _amount,totalNUON,collateralRequired);
        } else {
            return (0,0,0,0);
        }

        require(getUserLiquidityCoverage(_user,_amount) > liquidityCheck, "Increase your liquidity coverage");

    }

    /**
     * @notice Used to redeem a collateral amount without giving back NUON
     * @param _collateralAmount NUON amount to give back
     */
    function redeemWithoutNuon(uint256 _collateralAmount)
        external
        nonReentrant
    {
        require(
            INUONController(NUONController).isRedeemPaused() == false,
            'CHUB: Minting paused! Aaah!'
        );

        uint256 userAmount = usersAmounts[msg.sender];
        uint256 collateralAmount = _collateralAmount;
        require(userAmount > 0, 'You do not have any balance in that CHUB');
        require(collateralAmount < userAmount, "Cannot withdraw all the collaterals");

        usersAmounts[msg.sender] = userAmount.sub(collateralAmount);
        INLP(NLP)._addAmountToPosition(mintedAmount[msg.sender], usersAmounts[msg.sender], userLPs[msg.sender], nlpPerUser[msg.sender]);
        
        uint256 fees = collateralAmount
            .mul(INUONController(NUONController).getRedeemFee(address(this)))
            .div(100)
            .div(1e18);
        uint256 toUser = collateralAmount.sub(fees);
        
        if(getUserLiquidationStatus(msg.sender)) {
            revert("This will liquidate you");
        } else {
            IERC20Burnable(collateralUsed).transfer(msg.sender, toUser);
            IERC20Burnable(collateralUsed).transfer(Treasury,fees);
            emit redeemedWithoutNuon(msg.sender, fees, toUser);
        }
    }

    function _redeemWithoutNuonEstimation(uint256 _collateralAmount, address _user)
        public
        view
        returns(uint256,uint256,uint256)
    {
        uint256 ratio = INUONController(NUONController).getGlobalCollateralRatio(address(this));
        require(usersAmounts[_user] > 0, 'You do not have any balance in that CHUB');
        require(_collateralAmount < usersAmounts[_user], "Cannot withdraw all the collaterals");
        
        uint256 fees = _collateralAmount
            .mul(INUONController(NUONController).getRedeemFee(address(this)))
            .div(100)
            .div(1e18);
        uint256 toUser = _collateralAmount.sub(fees);

        if (viewUserCollateralAmount(_user) > 0) {
            uint256 camount = usersAmounts[_user].sub(_collateralAmount);
            uint256 userTVL = (camount * assetMultiplier) * getCollateralPrice() / 1e18;
            uint256 totalNUON = viewUserMintedAmount(_user);
            uint256 mintedValue =  totalNUON * getNUONPrice() / 1e18;
            uint256 result =  (userTVL * 1e18) / mintedValue * 100;
            uint256 rat = 1e18 * 1e18 / result * 100;
            require(rat < ratio, "This will liquidate you");
            return (result, toUser,camount);
        } else {
            return (0,0,0);
        }
    }

    /**
     * @notice Used to redeem a collateral amount without giving back NUON
     * @param _nuonAmount NUON amount to give back
     */
    function burnNUON(uint256 _nuonAmount)
        external
        nonReentrant
    {
        uint256 usernlp = nlpPerUser[msg.sender];
        require(
            INUONController(NUONController).isRedeemPaused() == false,
            'CHUB: Redeem paused! Aaah!'
        );

        uint256 nuonAmount = _nuonAmount;
        uint256 userAmount = usersAmounts[msg.sender];
        uint256 userMintedAmount = mintedAmount[msg.sender];

        require(userAmount > 0, 'You do not have any balance in that CHUB');
        uint256 maxBurn = userMintedAmount.mul(maxNuonBurnPercent).div(100);
        require(_nuonAmount < maxBurn, 'Cannot burn your whole balance of NUON');

        mintedAmount[msg.sender] = userMintedAmount.sub(nuonAmount);
        INLP(NLP)._addAmountToPosition(mintedAmount[msg.sender], usersAmounts[msg.sender], userLPs[msg.sender], nlpPerUser[msg.sender]);
        uint256 sharesToUser = redeemLiquidityHelper(nuonAmount,msg.sender);
        userLPs[msg.sender] = userLPs[msg.sender].sub(sharesToUser);

        if(getUserLiquidationStatus(msg.sender)) {
            revert("This will liquidate you");
        } else {
            IERC20Burnable(NUON).transferFrom(msg.sender, address(this), nuonAmount);
            uint256 lpToSend = _removeUserLPs(sharesToUser);
            IERC20Burnable(lpPair).transfer(msg.sender, lpToSend);
            IERC20Burnable(NUON).burn(nuonAmount);
            require(collateralPercentToRatio(msg.sender) >= INUONController(NUONController).getMaxCratio(address(this)),"Collateral Ratio too low");
            emit burnedNuon(msg.sender, nuonAmount, lpToSend);
        }
    }

    function _burnNUONEstimation(uint256 _NUONAmount, address _user) public view returns(uint256,uint256,uint256) {
        uint256 ratio = INUONController(NUONController).getGlobalCollateralRatio(address(this));

        require(usersAmounts[_user] > 0, 'You do not have any balance in that CHUB');
        uint256 maxBurn = mintedAmount[_user].mul(maxNuonBurnPercent).div(100);
        require(_NUONAmount < maxBurn, 'Cannot burn your whole balance of NUON');
        
        if (viewUserCollateralAmount(_user) > 0) {
            uint256 userTVL = (viewUserCollateralAmount(_user) * assetMultiplier) * getCollateralPrice() / 1e18;
            uint256 totalNUON = viewUserMintedAmount(_user).sub(_NUONAmount);
            uint256 mintedValue =  totalNUON * getNUONPrice() / 1e18;
            uint256 result =  (userTVL * 1e18) / mintedValue * 100;
            uint256 rat = 1e18 * 1e18 / result * 100;
            require(rat < ratio, "This will liquidate you");
            return (result, _NUONAmount, totalNUON);
        } else {
            return (0,0,0);
        }

    }

    function liquidateUserAssets(address _user) public {
        uint256 usernlp = nlpPerUser[_user];
        require(getUserLiquidationStatus(_user),"User cannot be liquidated");
        address router = unirouter;
        uint256 mintedAmount = mintedAmount[_user];
        uint256 userAmount = usersAmounts[_user];
        uint256 sharesAmount = userLPs[_user];
        
        INLP(NLP).burnNLP(usernlp);
        INLP(NLP)._deletePositionInfo(_user);
        _deleteUsersData(_user);

        (,uint256 collateralRequired) = mintLiquidityHelper(mintedAmount);
        uint256 liqProfit = userAmount - collateralRequired;
        IERC20Burnable(collateralUsed).approve(router, collateralRequired);

        uint256 balBefore = INUON(NUON).balanceOf(address(this));
        IUniswapRouterETH(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                collateralRequired,
                0,
                collateralToNuonRoute,
                address(this),
                block.timestamp
            );
        uint256 balAfter = INUON(NUON).balanceOf(address(this));

        INUON(NUON).burn(balAfter - balBefore);
        uint256 liqFee = liqProfit * liquidationFee / 1000;
        IERC20Burnable(collateralUsed).transfer(Treasury, liqProfit - liqFee);
        IERC20Burnable(collateralUsed).transfer(msg.sender, liqFee);
        uint256 lpToSend = _removeUserLPs(sharesAmount);
        IERC20Burnable(lpPair).transfer(_user, lpToSend);
    }

    /**
     * @notice View function used to compute the amount of NUON to be minted
     * @param collateralRatio Determined by the controller contract
     * @param collateralPrice Determined by the assigned oracle
     * @param collateralAmountD18 Collateral amount in d18 format
     * return The NUON amount to be minted
     */
    function calcOverCollateralizedMintAmounts(
        uint256 collateralRatio, // 500000000000000000
        uint256 collateralPrice, //20000000000000000000000
        uint256 collateralAmountD18 //15000000000000000000
    ) internal view returns (uint256) {
        uint256 collateralValue = (
            collateralAmountD18.mul(collateralPrice)).div(1e18);
        uint256 NUONValueToMint = collateralValue.mul(collateralRatio).div(ITruflation(TruflationOracle).getNuonTargetPeg());
        return NUONValueToMint;
    }

    /**
     * @notice View function used to compute the amount of collaterals given back to the user
     * @param collateralRatio Determined by the controller contract
     * @param collateralPrice Determined by the assigned oracle
     * @param NUONAmount NUON amount in d18 format
     * @param multiplier Collateral multiplier factor
     * return The amount of collateral out
     */
    function calcOverCollateralizedRedeemAmounts(
        uint256 collateralRatio,
        uint256 collateralPrice,
        uint256 NUONAmount,
        uint256 multiplier
    ) internal view returns (uint256) {
        uint256 NUONValueNeeded = (
            NUONAmount.mul(ITruflation(TruflationOracle).getNuonTargetPeg()).div(collateralRatio)
        ).mul(1e18);
        uint256 NUONAmountToBurn = (NUONValueNeeded.mul(multiplier).div(collateralPrice).div(1e18));
        return (NUONAmountToBurn);
    }

    function mintLiquidityHelper(uint256 _NUONAmountD18) internal view returns(uint256,uint256) {
        uint256 nuonValue = _NUONAmountD18.mul(getNUONPrice()).div(1e18);
        uint256 collateralRequired = nuonValue.mul(1e18).div(getCollateralPrice()).div(assetMultiplier);
        uint256 collateralBuffer = collateralRequired.mul(liquidityBuffer).div(100);
        return(collateralRequired.add(collateralBuffer),collateralRequired);
    }

    function redeemLiquidityHelper(uint256 _nuonAmount, address _user) internal view returns(uint256) {
        uint256 nuonAmount = _nuonAmount;
        uint256 lpAmount = userLPs[msg.sender];
        //we do not use the buffer for redeem
        (,uint256 collateralRequired) = mintLiquidityHelper(_nuonAmount);
        uint256 lpValue = getLPValueOfUser(_user);

        uint256 proportion = (collateralRequired.div(2)).mul(1e18).div(lpValue).mul(100);
        uint256 lpToUser = lpAmount.mul(proportion).div(1e18).div(100);
        return(lpToUser);
    }

    function getLPValueOfUser(address _user) internal view returns (uint256) {
        uint256 lpAmount = userLPs[_user].mul(IRelayer(Relayer).getPPFS()).div(1e18);
        uint256 userMintedAmount = mintedAmount[_user];

        uint256 collateralBal = IERC20Burnable(collateralUsed).balanceOf(lpPair);
        uint256 totalSupplyOf = IERC20Burnable(lpPair).totalSupply();
        uint256 lpValue = (lpAmount.mul(1e18).div(totalSupplyOf)).mul(collateralBal).div(1e18);
        return lpValue;
    }

    function getUserLiquidityCoverage(address _user, uint256 _extraAmount) public view returns(uint256) {
        uint256 lpValue = getLPValueOfUser(_user);
        uint256 userMintedAmount = mintedAmount[_user].add(_extraAmount);
        
        (,uint256 collateralRequired) = mintLiquidityHelper(userMintedAmount);
        uint256 coverage = lpValue.mul(1e18).div(collateralRequired).mul(100);
        
        return(coverage);
    }

    function _deleteUsersData(address _user) internal {
        mintedAmount[_user] = 0;
        usersAmounts[_user] = 0;
        userLPs[_user] = 0;
        delete users[usersIndex[_user]];
        usersIndex[_user] = 0;
        nlpCheck[_user] = false;
        delete nlpPerUser[_user];
    }

    function _reAssignNewOwnerBalances(address _user, address _receiver, bool _hasPosition, uint256 _tokenId) public {
        require(msg.sender == NLP, "Not the NLP");
        //if receiver does not have a position yet, we create one for him
        //otherwise we merge his actual position 
        if (_hasPosition == false) {
            mintedAmount[_receiver] = mintedAmount[_user];
            usersAmounts[_receiver] = usersAmounts[_user];
            userLPs[_receiver] = userLPs[_user];
            nlpPerUser[_receiver] = _tokenId;
            usersIndex[_receiver] = users.length;
            users.push(_receiver);
            nlpCheck[_receiver] = true;
            INLP(NLP)._addAmountToPosition(mintedAmount[_receiver], usersAmounts[_receiver], userLPs[_receiver],_tokenId);
        } else if (_hasPosition) {
            uint256 pos = getPositionOwned(_receiver);
            mintedAmount[_receiver] = mintedAmount[_receiver].add(mintedAmount[_user]);
            usersAmounts[_receiver] = usersAmounts[_receiver].add(usersAmounts[_user]);
            userLPs[_receiver] = userLPs[_receiver].add(userLPs[_user]);
            INLP(NLP)._topUpPosition(mintedAmount[_receiver], usersAmounts[_receiver], userLPs[_receiver],pos,_receiver);
            INLP(NLP)._deletePositionInfo(_user);
        }
        _deleteUsersData(_user);
    }
}
