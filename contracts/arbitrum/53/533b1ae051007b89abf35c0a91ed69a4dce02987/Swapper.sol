// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IUniswapV2Router02.sol";
import "./IElmt.sol";
import "./Owners.sol";

contract Swapper is Owners {
    struct Path {
        address[] pathIn;
        address[] pathOut;
    }

    struct MapPath {
        address[] keys;
        mapping(address => Path) values;
        mapping(address => uint256) indexOf;
        mapping(address => bool) inserted;
    }

    MapPath private mapPath;

    address public elmt;
    address public treasury;
    address public team;
    address public rewardsPool;
    address public lpHandler;
    address public router;
    address public native;
    address public pair;

    uint public treasuryMintFee;
    uint public rewardsMintFee;
    uint public lpMarketplaceFee;

    bool private swapping = false;
    bool private swapLiquifyCreate = true;
    bool private swapLiquifyClaim = true;
    bool private swapTreasury = true;
    bool private swapRewards = true;
    bool private swapLpPool = true;
    bool private swapTeam = true;

    uint public swapTokensAmountCreate;

    address public handler;

    bool public openSwapCreate = true;
    bool public openSwapClaim = true;
    bool public openSwapBurn = true;
    bool public openSwapMarketplace = true;

    constructor(address[] memory addresses, uint256[] memory fees, uint256 _swAmount, address _handler) {
        elmt = addresses[0];
        treasury = addresses[1];
        team = addresses[2];
        rewardsPool = addresses[3];
        lpHandler = addresses[4];
        router = addresses[5];
        native = addresses[6];
        pair = addresses[7];

        treasuryMintFee = fees[0];
        rewardsMintFee = fees[1];
        lpMarketplaceFee = fees[2];

        swapTokensAmountCreate = _swAmount;

        handler = _handler;
    }

    modifier onlyHandler() {
        require(msg.sender == handler, "Swapper: Only Handler");
        _;
    }

    function addMapPath(address token, address[] calldata pathIn, address[] calldata pathOut) external onlyOwners {
        require(!mapPath.inserted[token], "Swapper: Token already exists");
        mapPathSet(token, Path({pathIn: pathIn, pathOut: pathOut}));
    }

    function updateMapPath(address token, address[] calldata pathIn, address[] calldata pathOut) external onlyOwners {
        require(mapPath.inserted[token], "Swapper: Token doesnt exist");
        mapPathSet(token, Path({pathIn: pathIn, pathOut: pathOut}));
    }

    function removeMapPath(address token) external onlyOwners {
        require(mapPath.inserted[token], "Swapper: Token doesnt exist");
        mapPathRemove(token);
    }

    function swapCreate(address tokenIn, address user, uint price) external onlyHandler {
        require(openSwapCreate, "Swapper: Not open");
        _swapCreation(tokenIn, user, price);
    }

    function swapClaim(address user, uint rewardsTotal, uint feesTotal) external onlyHandler {
        require(openSwapClaim, "Swapper: Not open");
        _swapClaim(user, rewardsTotal, feesTotal);
    }

    function swapBurn(address user, uint price) external onlyHandler {
        require(openSwapBurn, "Swapper: Not open");
        _swapBurn(user, price);
    }

    function swapMarketplace(address user, uint price) external onlyHandler {
        require(openSwapMarketplace, "Swapper: Not open");
        _swapMarketplace(user, price);
    }

    // external setters
    function setElmt(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: Elmt cannot be address zero");
        elmt = _new;
    }

    function setTreasury(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: Treasury cannot be address zero");
        treasury = _new;
    }

    function setRewardsPool(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: RewardsPool cannot be address zero");
        rewardsPool = _new;
    }

    function setLpHandler(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: LpHandler cannot be address zero");
        lpHandler = _new;
    }

    function setRouter(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: Router cannot be address zero");
        router = _new;
    }

    function setNative(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: Native cannot be address zero");
        native = _new;
    }

    function setPair(address _new) external onlyOwners {
        require(_new != address(0), "Swapper: Pair cannot be address zero");
        pair = _new;
    }

    function settreasuryMintFee(uint _new) external onlyOwners {
        treasuryMintFee = _new;
    }

    function setrewardsMintFee(uint _new) external onlyOwners {
        rewardsMintFee = _new;
    }

    function setlpMarketplaceFee(uint _new) external onlyOwners {
        lpMarketplaceFee = _new;
    }

    function setSwapLiquifyCreate(bool _new) external onlyOwners {
        swapLiquifyCreate = _new;
    }

    function setSwapLiquifyClaim(bool _new) external onlyOwners {
        swapLiquifyClaim = _new;
    }

    function setSwapTreasury(bool _new) external onlyOwners {
        swapTreasury = _new;
    }

    function setSwapRewards(bool _new) external onlyOwners {
        swapRewards = _new;
    }

    function setSwapLpPool(bool _new) external onlyOwners {
        swapLpPool = _new;
    }

    function setSwapTeam(bool _new) external onlyOwners {
        swapTeam = _new;
    }

    function setSwapTokensAmountCreate(uint _new) external onlyOwners {
        swapTokensAmountCreate = _new;
    }

    function setOpenSwapCreate(bool _new) external onlyOwners {
        openSwapCreate = _new;
    }

    function setOpenSwapClaim(bool _new) external onlyOwners {
        openSwapClaim = _new;
    }

    function setOpenSwapBurn(bool _new) external onlyOwners {
        openSwapBurn = _new;
    }

    function setOpenSwapMarketplace(bool _new) external onlyOwners {
        openSwapMarketplace = _new;
    }

    // external view
    function getMapPathSize() external view returns (uint) {
        return mapPath.keys.length;
    }

    function getMapPathKeysBetweenIndexes(uint iStart, uint iEnd) external view returns (address[] memory) {
        address[] memory keys = new address[](iEnd - iStart);
        for (uint i = iStart; i < iEnd; i++) keys[i - iStart] = mapPath.keys[i];
        return keys;
    }

    function getMapPathBetweenIndexes(uint iStart, uint iEnd) external view returns (Path[] memory) {
        Path[] memory path = new Path[](iEnd - iStart);
        for (uint i = iStart; i < iEnd; i++) path[i - iStart] = mapPath.values[mapPath.keys[i]];
        return path;
    }

    function getMapPathForKey(address key) external view returns (Path memory) {
        require(mapPath.inserted[key], "Swapper: Key doesnt exist");
        return mapPath.values[key];
    }

    // internal
    function _swapCreation(address tokenIn, address user, uint price) internal {
        require(price > 0, "Swapper: Nothing to swap");

        if (tokenIn == elmt) {
            IElmt(elmt).transferFrom(user, address(this), price);
            _swapCreationElmt();
        } else {
            _swapCreationToken(tokenIn, user, price);
            _swapCreationElmt();
        }
    }

    function _swapMarketplace(address user, uint price) internal {
        require(price > 0, "Swapper: Nothing to swap");

        IElmt(elmt).transferFrom(user, address(this), price);
        _swapMarketplaceElmt();
    }

    function _swapBurn(address user, uint price) internal {
        require(price > 0, "Swapper: Nothing to burn");
        IElmt(elmt).transferFrom(user, address(this), price);
        IElmt(elmt).burnFrom(user, price);
    }

    function _swapCreationElmt() internal {
        uint256 contractTokenBalance = IElmt(elmt).balanceOf(address(this));

        if (contractTokenBalance >= swapTokensAmountCreate && swapLiquifyCreate && !swapping) {
            swapping = true;

            if (swapTreasury) {
                uint256 treasuryTokens = (contractTokenBalance * treasuryMintFee) / 10000;
                swapAndSendToAddress(treasury, treasuryTokens);
            }

            if (swapRewards) {
                uint256 rewardsPoolTokens = (contractTokenBalance * rewardsMintFee) / 10000;
                IElmt(elmt).transfer(rewardsPool, rewardsPoolTokens);
            }

            if (swapTeam) {
                uint256 teamTokens = IElmt(elmt).balanceOf(address(this));
                swapAndSendToAddress(team, teamTokens);
            }

            swapping = false;
        }
    }

    function _swapCreationToken(address tokenIn, address user, uint price) internal {
        require(mapPath.inserted[tokenIn], "Swapper: Unknown token");

        uint toTransfer = IUniswapV2Router02(router).getAmountsIn(price, mapPath.values[tokenIn].pathIn)[0];

        IElmt(tokenIn).transferFrom(user, address(this), toTransfer);

        IElmt(tokenIn).approve(router, toTransfer);

        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            toTransfer,
            0, // if transfer fee
            mapPath.values[tokenIn].pathIn,
            address(this),
            block.timestamp
        );
    }

    function _swapMarketplaceElmt() internal {
        uint256 contractTokenBalance = IElmt(elmt).balanceOf(address(this));

        if (contractTokenBalance >= swapTokensAmountCreate && swapLiquifyCreate && !swapping) {
            swapping = true;

            // lp
            if (swapLpPool) {
                uint256 swapTokens = (contractTokenBalance * lpMarketplaceFee) / 10000;
                swapAndLiquify(swapTokens);
            }

            // team
            if (swapTeam) {
                uint256 teamTokens = IElmt(elmt).balanceOf(address(this));
                swapAndSendToAddress(team, teamTokens);
            }

            swapping = false;
        }
    }

	function _swapClaim(
		address user, 
		uint rewardsTotal, 
		uint feesTotal
	) 
		internal 
	{
		if (rewardsTotal + feesTotal > 0) {
			if (swapLiquifyClaim)
				IElmt(elmt).transferFrom(rewardsPool, address(this), rewardsTotal + feesTotal);
			else if (rewardsTotal > 0)
				IElmt(elmt).transferFrom(rewardsPool, address(this), rewardsTotal);

			if (rewardsTotal > 0)
				IElmt(elmt).transfer(user, rewardsTotal);

		}
	}

    function swapAndSendToAddress(address destination, uint256 tokens) private {
        bool success;
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = (address(this).balance) - initialETHBalance;
        (success, ) = address(destination).call{value: newBalance}("");
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance - initialBalance;

        addLiquidity(otherHalf, newBalance);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = elmt;
        path[1] = IUniswapV2Router02(router).WETH();

        IElmt(elmt).approve(router, tokenAmount);

        IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        IElmt(elmt).approve(router, tokenAmount);

        IUniswapV2Router02(router).addLiquidityETH{value: ethAmount}(elmt, tokenAmount, 0, 0, lpHandler, block.timestamp);
    }

    function mapPathSet(address key, Path memory value) private {
        if (mapPath.inserted[key]) {
            mapPath.values[key] = value;
        } else {
            mapPath.inserted[key] = true;
            mapPath.values[key] = value;
            mapPath.indexOf[key] = mapPath.keys.length;
            mapPath.keys.push(key);
        }
    }

    function mapPathRemove(address key) private {
        if (!mapPath.inserted[key]) {
            return;
        }

        delete mapPath.inserted[key];
        delete mapPath.values[key];

        uint256 index = mapPath.indexOf[key];
        uint256 lastIndex = mapPath.keys.length - 1;
        address lastKey = mapPath.keys[lastIndex];

        mapPath.indexOf[lastKey] = index;
        delete mapPath.indexOf[key];

        if (lastIndex != index) mapPath.keys[index] = lastKey;
        mapPath.keys.pop();
    }
}

