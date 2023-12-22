// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Strings.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./console.sol";

contract PoolMaster is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public token;
    IERC20 public usdc;
    
    uint256 public bettingPhaseDuration = 8 * 60 * 60; // 8 Hours
    uint256 public battlingPhaseDuration = 24 * 60 * 60; // 24 Hours

    uint256 public loserTokensPercent = 1250; // 12.50 %
    uint256 public winnerTokensPercent = 8000; // 10.00 % : 10/12.5 = 80%
    uint256 public burnedTokensPercent = 400; // 0.50% : 0.5/12.5 = 4%
    uint256 public pool3TokensPercent = 1600; // 2.00% : 2/12.5 = 16%
    
    uint256 public unstakeFee = 200; // 2.00%
    uint256 public usdcStakeFee = 100; // 1.00%

    bool public epochEnded = true;
    uint256 public timestampStartEpoch;

    Pool[] private pools;
    mapping(address => Staker) private stakersMapping;
    Staker[] private stakersPool1;
    Staker[] private stakersPool2;
    Staker[] private stakersPool3;
    
    WinnerAddress[] private winAddresses;

    struct Pool {
        string symbol;
        string lastWinnerSymbol;
        uint256 tokenCount;
        uint256 usdcCount;
        uint256 tokenStakers;
        uint256 usdcStakers;
    }

    struct Staker {
        uint256 poolId;
        uint256 amount;
        bool isUsdc;
        address stakerAddress;
    }

    struct WinnerAddress {
        uint256 amount;
        bool isUsdc;
        address stakerAddress;
        uint256 timestampWon;
    }


    event MintSuccessful(address user, uint256 tokenId, bool isAlpha);

    constructor() {
        pools.push(Pool("", "", 0, 0, 0, 0));
        pools.push(Pool("", "", 0, 0, 0, 0));
        pools.push(Pool("", "", 0, 0, 0, 0));
    }

    function stake(uint256 _poolId, uint256 _amount, bool _isUsdc) public payable {
        require(!epochEnded, "Epoch not started yet");
        require(getPhase() == 0, "Betting phase has ended.");

        require(_poolId <= 2, "Invalid pool Id");
        require(!(_poolId == 2 && _isUsdc), "Cannot stake usdc in third pool.");
        require(stakersMapping[msg.sender].stakerAddress == address(0), "User already staked for this epoch");

        uint256 _stakeAmount = _amount;
        if (_isUsdc) {
            require(_poolId <= 1, "Invalid pool Id");
            _stakeAmount = (_amount * (10_000 - usdcStakeFee)) / 10_000;
            usdc.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            token.safeTransferFrom(msg.sender, address(this), _amount);
        }
        require(_stakeAmount > 0, "Must stake more than 0 tokens");

        Staker memory _staker = Staker(_poolId, _stakeAmount, _isUsdc, msg.sender);
        
        stakersMapping[msg.sender] = _staker;
        pools[_poolId].tokenCount += _isUsdc ? 0 : _amount;
        pools[_poolId].usdcCount += _isUsdc ? _amount : 0;
        pools[_poolId].tokenStakers += _isUsdc ? 0 : 1;
        pools[_poolId].usdcStakers += _isUsdc ? 1 : 0;

        if (_poolId == 0) {
            stakersPool1.push(_staker);
        } else if (_poolId == 1) {
            stakersPool2.push(_staker);
        } else if (_poolId == 2) {
            stakersPool3.push(_staker);
        }
    }

    function startEpoch(string calldata _symbol1, string calldata _symbol2) public onlyOwner {
        require(epochEnded, "Current epoch has not ended");
        epochEnded = false;

        pools[0].symbol = _symbol1;
        pools[1].symbol = _symbol2;

        pools[0].tokenCount = 0;
        pools[1].tokenCount = 0;
        pools[2].tokenCount = 0;

        pools[0].usdcCount = 0;
        pools[1].usdcCount = 0;
        pools[2].usdcCount = 0;

        pools[0].tokenStakers = 0;
        pools[1].tokenStakers = 0;
        pools[2].tokenStakers = 0;

        pools[0].usdcStakers = 0;
        pools[1].usdcStakers = 0;
        pools[2].usdcStakers = 0;

        timestampStartEpoch = block.timestamp;
    }

    // Der Pool, dessen token den anderen in absoluten % outperformt hat, gewinnt
    function endEpoch(uint256 _poolWinnerId) public onlyOwner {
        require(!epochEnded, "Current epoch already ended");
        require(getPhase() == 2, "Epoch not ready to be ended yet.");
        epochEnded = true;

        uint256 _poolLoserId = 1 - _poolWinnerId;
        uint256 _poolLoserLength = _poolLoserId == 0 ? stakersPool1.length : stakersPool2.length;
        uint256 _poolWinnerLength = _poolWinnerId == 0 ? stakersPool1.length : stakersPool2.length;

        pools[_poolLoserId].lastWinnerSymbol = "";
        pools[_poolWinnerId].lastWinnerSymbol = pools[_poolWinnerId].symbol;

        uint256 _tokenLostAmount = 0;
        uint256 _usdcLostAmount = 0;
        // Verlierer kriegen 12.5% ihrer gestakten Tokens abgezogen
        for(uint256 i = 0; i < _poolLoserLength;) {
            Staker memory _staker = _poolLoserId == 0 ? stakersPool1[i] : stakersPool2[i];

            uint256 _userLoseAmount = (_staker.amount * loserTokensPercent) / 10_000;
            uint256 _userKeepAmount = _staker.amount - _userLoseAmount;

            console.log("_userLoseAmount");
            console.log(_userLoseAmount);
            console.log("_userKeepAmount");
            console.log(_userKeepAmount);

            if (_staker.isUsdc) {
                usdc.transfer(_staker.stakerAddress, _userKeepAmount);
                _usdcLostAmount += _userLoseAmount;
            } else {
                token.transfer(_staker.stakerAddress, _userKeepAmount);
                _tokenLostAmount += _userLoseAmount;
            }

            stakersMapping[_staker.stakerAddress] = Staker(0, 0, false, address(0));
            unchecked { ++ i; }
        }

        // 10% davon wird an die Gewinner aufgeteilt
        uint256 _tokenWinningTokenPool = (_tokenLostAmount * winnerTokensPercent) / 10_000;
        uint256 _usdcWinningTokenPool = (_usdcLostAmount * winnerTokensPercent) / 10_000;
        uint256 _tokenUserWinAmount = 0;
        uint256 _usdcUserWinAmount = 0;
        console.log("pools[_poolWinnerId].tokenStakers");
        console.log(_poolWinnerId);
        console.log(pools[_poolWinnerId].tokenStakers);
        if (pools[_poolWinnerId].tokenStakers > 0) {
            _tokenUserWinAmount = _tokenWinningTokenPool / pools[_poolWinnerId].tokenStakers;
        }
        if (pools[_poolWinnerId].usdcStakers > 0) {
            _usdcUserWinAmount = _usdcWinningTokenPool / pools[_poolWinnerId].usdcStakers;
        }
        console.log("_tokenUserWinAmount");
        console.log(_tokenUserWinAmount);
        console.log("_tokenWinningTokenPool");
        console.log(_tokenWinningTokenPool);
        console.log("pools[_poolWinnerId].tokenStakers");
        console.log(pools[_poolWinnerId].tokenStakers);

        for(uint256 i = 0; i < _poolWinnerLength;) {
            Staker memory _staker = _poolWinnerId == 0 ? stakersPool1[i] : stakersPool2[i];
            if (_staker.isUsdc) {
                usdc.transfer(_staker.stakerAddress, _staker.amount + _usdcUserWinAmount);
                winAddresses.push(WinnerAddress(_usdcUserWinAmount, _staker.isUsdc, _staker.stakerAddress, block.timestamp));
            } else {
                token.transfer(_staker.stakerAddress, _staker.amount + _tokenUserWinAmount);
                winAddresses.push(WinnerAddress(_tokenUserWinAmount, _staker.isUsdc, _staker.stakerAddress, block.timestamp));
            }

            stakersMapping[_staker.stakerAddress] = Staker(0, 0, false, address(0));
            unchecked { ++ i; }
        }

        // 0.5% geburned
        uint256 _tokenBurnAmount = (_tokenLostAmount * burnedTokensPercent) / 10_000;
        uint256 _usdcBurnAmount = (_usdcLostAmount * burnedTokensPercent) / 10_000;
        usdc.transfer(0x000000000000000000000000000000000000dEaD, _usdcBurnAmount);
        token.transfer(0x000000000000000000000000000000000000dEaD, _tokenBurnAmount);

        // die restlichen 2% geht an Pool3 staker
        uint256 _pool3Length = stakersPool3.length;
        uint256 _tokenPool3Amount = (_tokenLostAmount * pool3TokensPercent) / 10_000;
        uint256 _usdcPool3Amount = (_usdcLostAmount * pool3TokensPercent) / 10_000;
        uint256 _tokenUserPool3Amount = 0;
        uint256 _usdcUserPool3Amount = 0;
        // console.log("pools[2].tokenCount");
        // console.log(pools[2].tokenCount);
        if (pools[2].tokenStakers > 0) {
            _tokenUserPool3Amount = _tokenPool3Amount / pools[2].tokenStakers;
        }
        if (pools[2].usdcStakers > 0) {
            _usdcUserPool3Amount = _usdcPool3Amount / pools[2].usdcStakers;
        }

        for(uint256 i = 0; i < _pool3Length;) {
            Staker memory _staker = stakersPool3[i];

            if (_staker.isUsdc) {
                usdc.transfer(_staker.stakerAddress, _staker.amount + _usdcUserPool3Amount);
            } else {
                token.transfer(_staker.stakerAddress, _staker.amount + _tokenUserPool3Amount);
            }

            stakersMapping[_staker.stakerAddress] = Staker(0, 0, false, address(0));
            unchecked { ++ i; }
        }

        delete stakersPool1;
        delete stakersPool2;
        delete stakersPool3;
    }

    // GETTERS

    function getPhase() public view returns (uint256) {
        uint256 _timeElapsed = block.timestamp - timestampStartEpoch;
        if (_timeElapsed > battlingPhaseDuration || epochEnded)
            return 2; // epoch ended
        else if (_timeElapsed > bettingPhaseDuration)
            return 1; // battling phase
        return 0; // betting phase
    }

    function getStakedTokensForAddress(address _user) public view returns (uint256) {
        return stakersMapping[_user].amount;
    }

    function getIsUsdcForAddress(address _user) public view returns (bool) {
        return stakersMapping[_user].isUsdc;
    }

    function getPoolIdForAddress(address _user) public view returns (uint256) {
        return stakersMapping[_user].poolId;
    }

    function getStakedTokens(uint256 _poolId, bool _isUsdc) public view returns (uint256) {
        return _isUsdc ? pools[_poolId].usdcCount : pools[_poolId].tokenCount;
    }

    function getLastWinner(uint256 _poolId) public view returns (string memory) {
        return pools[_poolId].lastWinnerSymbol;
    }

    function getSymbol(uint256 _poolId) public view returns (string memory) {
        return pools[_poolId].symbol;
    }

    function getWinnerAddressAmountsForLastSeconds(uint256 _lastSeconds) public view returns (uint256[] memory) {
        uint256 _currentTimestamp = block.timestamp;
        uint256 _winnersLength = winAddresses.length;
        
        uint256 arrayLength = 0;
        for(uint256 i = 0; i < _winnersLength;) {
            if (winAddresses[i].timestampWon + _lastSeconds > _currentTimestamp)
                arrayLength ++;
            unchecked { ++ i; }
        }
        
        uint256[] memory _amounts = new uint256[](arrayLength);
        for(uint256 i = 0; i < _winnersLength;) {
            if (winAddresses[i].timestampWon + _lastSeconds > _currentTimestamp)
                _amounts[i] = winAddresses[i].amount;
            unchecked { ++ i; }
        }

        return _amounts;
    }

    function getWinnerAddressStakerAddressForLastSeconds(uint256 _lastSeconds) public view returns (address[] memory) {
        uint256 _currentTimestamp = block.timestamp;
        uint256 _winnersLength = winAddresses.length;
        
        uint256 arrayLength = 0;
        for(uint256 i = 0; i < _winnersLength;) {
            if (winAddresses[i].timestampWon + _lastSeconds > _currentTimestamp)
                arrayLength ++;
            unchecked { ++ i; }
        }
        
        address[] memory _addresses = new address[](arrayLength);
        for(uint256 i = 0; i < _winnersLength;) {
            if (winAddresses[i].timestampWon + _lastSeconds > _currentTimestamp)
                _addresses[i] = winAddresses[i].stakerAddress;
            unchecked { ++ i; }
        }
        return _addresses;
    }

    function getWinnerAddressIsUsdcForLastSeconds(uint256 _lastSeconds) public view returns (bool[] memory) {
        uint256 _currentTimestamp = block.timestamp;
        uint256 _winnersLength = winAddresses.length;
        
        uint256 arrayLength = 0;
        for(uint256 i = 0; i < _winnersLength;) {
            if (winAddresses[i].timestampWon + _lastSeconds > _currentTimestamp)
                arrayLength ++;
            unchecked { ++ i; }
        }
        
        bool[] memory _isUsdc = new bool[](arrayLength);
        for(uint256 i = 0; i < _winnersLength;) {
            if (winAddresses[i].timestampWon + _lastSeconds > _currentTimestamp)
                _isUsdc[i] = winAddresses[i].isUsdc;
            unchecked { ++ i; }
        }
        return _isUsdc;
    }

    // SETTERS

    function setBettingPhaseDuration(uint256 _bettingPhaseDuration) public onlyOwner {
        bettingPhaseDuration = _bettingPhaseDuration;
    }

    function setBattlingPhaseDuration(uint256 _battlingPhaseDuration) public onlyOwner {
        battlingPhaseDuration = _battlingPhaseDuration;
    }

    function setLoserTokensPercent(uint256 _loserTokensPercent) public onlyOwner {
        loserTokensPercent = _loserTokensPercent;
    }

    function setWinnerTokensPercent(uint256 _winnerTokensPercent) public onlyOwner {
        winnerTokensPercent = _winnerTokensPercent;
    }

    function setBurnedTokensPercent(uint256 _burnedTokensPercent) public onlyOwner {
        burnedTokensPercent = _burnedTokensPercent;
    }

    function setPool3TokensPercent(uint256 _pool3TokensPercent) public onlyOwner {
        pool3TokensPercent = _pool3TokensPercent;
    }

    function setUsdcAddress(address _usdcAddress) public onlyOwner {
        usdc = IERC20(_usdcAddress);
    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        token = IERC20(_tokenAddress);
    }

    function setUnstakeFee(uint256 _unstakeFee) public onlyOwner {
        unstakeFee = _unstakeFee;
    }

    function setUsdcStakeFee(uint256 _usdcStakeFee) public onlyOwner {
        usdcStakeFee = _usdcStakeFee;
    }

    // OWNER FUNCTIONS
    
    function withdrawEth() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function withdrawToken() external onlyOwner {
        token.transfer(msg.sender, usdc.balanceOf(address(this)));
    }
    
    function withdrawUsdc() external onlyOwner {
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
    }
}

