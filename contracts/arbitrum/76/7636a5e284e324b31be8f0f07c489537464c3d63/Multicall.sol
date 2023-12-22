// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "./ERC20.sol";
import "./IERC20.sol";
import "./IERC721.sol";

interface IFactory {
    function totalDeployed() external view returns (uint256 length);
    function deployInfo(uint256 id) external view returns (address token, address nft, address gumbar, bool _allowed);
}

interface IBondingCurve {
    function currentPrice() external view returns (uint256);
    function buy(uint256 _amountBASE, uint256 _minGBT, uint256 expireTimestamp) external;
    function sell(uint256 _amountGBT, uint256 _minETH, uint256 expireTimestamp) external;
    function BASE_TOKEN() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function XGBT() external view returns (address);
    function initial_totalSupply() external view returns (uint256);
    function reserveGBT() external view returns (uint256);
    function borrowCredit(address user) external view returns (uint256);
    function debt(address user) external view returns (uint256);
    function reserveVirtualBASE() external view returns (uint256);
    function reserveRealBASE() external view returns (uint256);
    function floorPrice() external view returns (uint256);
    function mustStayGBT(address user) external view returns (uint256);
}

interface IGumball {
    function approve(address to, uint256 tokenId) external;
    function swapForExact(uint256[] memory id) external;
    function swap(uint256 _amount) external;
    function redeem(uint256[] memory _id) external;
    function gumballs() external view returns (uint256[] memory arr);
    function totalSupply() external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function contractURI() external view returns (string memory);
    function bFee() external view returns (uint256);
}

interface IGumbar {
    function GBTperXGBT() external view returns (uint256);
    function gumballsDeposited(address user) external view returns (uint256, uint256[] memory);
    function balanceOfNFT(address user) external view returns (uint256, uint256[] memory);
    function getRewardForDuration(address _rewardsToken) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function rewardTokens() external view returns (address[] memory);
    function earned(address account, address _rewardsToken) external view returns (uint256);
}

contract Multicall {

    address factory;

    struct Response {
        uint256 ethRewardForDuration;
        uint256 gbtRewardForDuration;
        uint256 currentPrice;
        uint256 totalSupply;
    }

    struct RewardData {
        address rewardToken;
        string symbol;
    }

    struct UserData {
        // General
        uint256 currentPrice;
        uint256 ltv;
        // Base token
        address baseToken;
        string baseSymbol;
        string baseName;
        uint256 baseBal;
        // ERC20BondingCurve
        uint256 gbtBalanceOfUser;
        uint256 gbtTotalSupply;
        uint256 redemptionFee;
        // Gumbar
        uint256 gbtStaked;
        uint256 ethEarned;
        uint256 gbtEarned;
        uint256 mustStayGBT;
        RewardData[] rewardData;
        uint256[] stakedGumballs;
        uint256[] unstakedGumballs;
        // Available borrow
        uint256 borrowCredit;
        uint256 debt;
        // Reserve values
        uint256 virtualBase;
        uint256 reserveRealBase;
        uint256 reserveGBT;
        // APR calculation values
        uint256 ethRewardForDuration;
        uint256 gbtRewardForDuration;
        uint256 totalSupply;
    }

    struct CollectionData {
        uint256 deploymentIndex;
        address baseToken;
        string baseTokenSymbol;
        string contractURI;
        uint256 currentPrice;
    }

    constructor(
        address _factory
    ) {
        factory = _factory;
    }

    function call(address[] memory collections) external view returns (Response[] memory response) {

        Response[] memory r = new Response[](collections.length);

        for (uint256 i = 0; i < collections.length; i++) {
            (uint256 index, bytes14 kind) = findDeployment(collections[i]);

            if (kind == bytes14("token")) {
                address gumbar = IBondingCurve(collections[i]).XGBT();
                r[i].ethRewardForDuration = IGumbar(gumbar).getRewardForDuration(IBondingCurve(collections[i]).BASE_TOKEN());
                r[i].gbtRewardForDuration = IGumbar(gumbar).getRewardForDuration(collections[i]);
                r[i].currentPrice = IBondingCurve(collections[i]).currentPrice();
                r[i].totalSupply = IGumbar(gumbar).totalSupply();
            }

            if (kind == bytes14("gumball")) {
                (address gbt, , , ) = IFactory(factory).deployInfo(index);
                ( , , address gumbar, ) = IFactory(factory).deployInfo(index);
                r[i].ethRewardForDuration = IGumbar(gumbar).getRewardForDuration(IBondingCurve(gbt).BASE_TOKEN());
                r[i].gbtRewardForDuration = IGumbar(gumbar).getRewardForDuration(gbt);
                r[i].currentPrice = IBondingCurve(gbt).currentPrice();
                r[i].totalSupply = IGumbar(gumbar).totalSupply();
            }
        }

        return r;
    }

    function _gbtPerEth(address collection) public view returns (uint256) {
        
        uint256 GBTperETH = IBondingCurve(collection).reserveGBT() * 1e18 / (IBondingCurve(collection).reserveVirtualBASE() + IBondingCurve(collection).reserveRealBASE());

        return GBTperETH;
    }

    function collectionData(address[] memory gbtAddressForCollection) external view returns (CollectionData[] memory _collectionData) {
        
        CollectionData[] memory cd = new CollectionData[](gbtAddressForCollection.length);

        for (uint256 j = 0; j < gbtAddressForCollection.length; j++) {

            for (uint256 i = 0; i < IFactory(factory).totalDeployed(); i++) {

            (address gbt, address gnft, , ) = IFactory(factory).deployInfo(i);

                if (gbt == gbtAddressForCollection[j]) {
                    cd[j].deploymentIndex = i;
                    cd[j].baseToken = IBondingCurve(gbtAddressForCollection[j]).BASE_TOKEN();
                    cd[j].baseTokenSymbol = ERC20(cd[j].baseToken).symbol();
                    cd[j].contractURI = IGumball(gnft).contractURI();
                    cd[j].currentPrice = IBondingCurve(gbtAddressForCollection[j]).currentPrice();
                }
            }
        }
        
        return cd;
    }

    function userData(address user, address gbtAddressForCollection) external view returns (UserData memory userdata) {

        UserData memory u;

        (uint256 index, ) = findDeployment(gbtAddressForCollection);

            (address gbt, address gumball , address gumbar , ) = IFactory(factory).deployInfo(index); 
            IERC20 base = IERC20(IBondingCurve(gbt).BASE_TOKEN());

            u.currentPrice = IBondingCurve(gbt).currentPrice();

            if (IBondingCurve(gbt).debt(user) == 0 || user == address(0x0000000000000000000000000000000000000000)) {
                u.ltv = 0;
            } else {
                u.ltv = 100 * IBondingCurve(gbt).debt(user) * _gbtPerEth(gbt) / (IGumbar(gumbar).balanceOf(user));
            }

            u.baseToken = address(base);
            u.baseSymbol = ERC20(address(base)).symbol();
            u.baseName = ERC20(address(base)).name();
            u.gbtTotalSupply = IERC20(gbt).totalSupply();
            u.redemptionFee = IGumball(gumball).bFee();
            u.gbtStaked = IGumbar(address(gumbar)).balanceOf(user);
            u.ethEarned = IGumbar(address(gumbar)).earned(user, u.baseToken);
            u.gbtEarned = IGumbar(address(gumbar)).earned(user, address(gbt));

            address[] memory tok = IGumbar(address(gumbar)).rewardTokens();
 
            RewardData[] memory rd = new RewardData[](tok.length);

            for (uint256 i = 0; i < tok.length; i++) {
                rd[i].rewardToken = tok[i];
                rd[i].symbol = ERC20(tok[i]).symbol();
            }

            u.rewardData = rd;
            
            ( , uint256[] memory arr) = IGumbar(address(gumbar)).balanceOfNFT(user);

            if (arr.length == 0) {
                // do nothing
            } else {
                u.stakedGumballs = arr;
            }
            
            uint256[] memory tokenIds = new uint256[](IERC721(gumball).balanceOf(user));

            if (IERC721(gumball).balanceOf(user) == 0) {
                uint256[] memory empty;
                u.unstakedGumballs = empty;
            } else {
                for (uint256 i = 0; i < IERC721(gumball).balanceOf(user); i++) {
                    tokenIds[i] = IGumball(gumball).tokenOfOwnerByIndex(user, i);
                }
                u.unstakedGumballs = tokenIds;
            }
            
            u.virtualBase = IBondingCurve(address(gbt)).reserveVirtualBASE();
            u.reserveRealBase = IBondingCurve(address(gbt)).reserveRealBASE();
            u.reserveGBT = IBondingCurve(address(gbt)).reserveGBT();

            u.ethRewardForDuration = IGumbar(gumbar).getRewardForDuration(IBondingCurve(address(gbt)).BASE_TOKEN());
            u.gbtRewardForDuration = IGumbar(gumbar).getRewardForDuration(address(gbt));
            u.totalSupply = IGumbar(gumbar).totalSupply();

            if (user == address(0x0000000000000000000000000000000000000000)) {
                u.baseBal = 0;
                u.gbtBalanceOfUser = 0;
                u.mustStayGBT = 0;
                u.borrowCredit = 0;
                u.debt = 0;
            } else {
                u.baseBal = base.balanceOf(user);
                u.gbtBalanceOfUser = IERC20(gbt).balanceOf(user);
                u.mustStayGBT = IBondingCurve(address(gbt)).mustStayGBT(user);
                u.borrowCredit = IBondingCurve(address(gbt)).borrowCredit(user);
                u.debt = IBondingCurve(address(gbt)).debt(user);
            }

        return u;
    }

    function totalCollections() public view returns (uint256) {
        return IFactory(factory).totalDeployed();
    }

    function findDeployment(address toFind) public view returns (uint256 _index, bytes14 _type) {

        bool found = false;

        for(uint256 i = 0; i < IFactory(factory).totalDeployed(); i++) {

            (address gbt, , , ) = IFactory(factory).deployInfo(i);
            (, address gumball, , ) = IFactory(factory).deployInfo(i);
            
            if (gbt == toFind) {
                found = true;
                return (i, bytes14('token'));
            } else if (gumball == toFind) {
                found = true;
                return (i, bytes14('gumball'));
            }
        }

        if (!found) {
            revert ('Address not found!');
        }
    }
}
