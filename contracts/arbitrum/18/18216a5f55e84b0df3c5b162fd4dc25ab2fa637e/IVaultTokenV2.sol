pragma solidity >=0.5.0;

import "./IMasterChef.sol";
import "./IUniswapV2Router01.sol";

interface IVaultTokenV2 {
    /*** Tarot ERC20 ***/

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /*** Pool Token ***/

    event Mint(
        address indexed sender,
        address indexed minter,
        uint256 mintAmount,
        uint256 mintTokens
    );
    event Redeem(
        address indexed sender,
        address indexed redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    );
    event Sync(uint256 totalBalance);

    function underlying() external view returns (address);

    function factory() external view returns (address);

    function totalBalance() external view returns (uint256);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function exchangeRate() external view returns (uint256);

    function mint(address minter) external returns (uint256 mintTokens);

    function redeem(address redeemer) external returns (uint256 redeemAmount);

    function skim(address to) external;

    function sync() external;

    function _setFactory() external;

    /*** VaultToken ***/

    event Reinvest(address indexed caller, uint256 reward, uint256 bounty, uint256 fee);

    function isVaultToken() external pure returns (bool);

    function router() external view returns (IUniswapV2Router01);

    function masterChef() external view returns (IMasterChef);

    function rewardsToken() external view returns (address);

    function WETH() external view returns (address);

    function reinvestFeeTo() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function pid() external view returns (uint256);

    function REINVEST_BOUNTY() external pure returns (uint256);

    function REINVEST_FEE() external view returns (uint256);

    function reinvestorListLength() external view returns (uint256);

    function reinvestorListItem(uint256 index) external view returns (address);

    function isReinvestorEnabled(address reinvestor) external view returns (bool);

    function addReinvestor(address reinvestor) external;

    function removeReinvestor(address reinvestor) external;

    function updateReinvestBounty(uint256 _newReinvestBounty) external;

    function updateReinvestFee(uint256 _newReinvestFee) external;

    function updateReinvestFeeTo(address _newReinvestFeeTo) external;

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function _initialize(
        address optiSwap,
        IUniswapV2Router01 _router,
        IMasterChef _masterChef,
        address _rewardsToken,
        uint256 _pid,
        address _reinvestFeeTo
    ) external;

    function reinvest() external;
}

