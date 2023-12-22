// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Inscription.sol";
import "./String.sol";
import "./TransferHelper.sol";
import "./Counters.sol";
import "./Ownable.sol";
import "./InscriptionProxy.sol";

contract InscriptionFactory is Ownable {
    using String for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _inscriptionNumbers;

    uint8 public maxTickSize = 4; // tick(symbol) length is 4.
    uint256 public baseFee = 0.0005 ether; // Will charge 0.00025 ETH as extra min tip from the second time of mint in the frozen period. And this tip will be double for each mint.
    uint256 public fundingCommission = 100; // commission rate of fund raising, 100 means 1%

    mapping(uint256 => Token) private inscriptions; // key is inscription id, value is token data
    mapping(string => uint256) private ticks; // Key is tick, value is inscription id

    address public platformAddress = address(0x0); // platform token contract address
    uint256 public platformMinQuantity = 0;
    uint256 public platformDeployQuantity = 0;
    uint256 public mintBurnPlatformQuantity = 0;

    event DeployInscription(
        uint256 indexed id,
        string tick,
        string name,
        uint256 cap,
        uint256 limitPerMint,
        address inscriptionAddress,
        uint256 timestamp
    );

    struct Token {
        string tick; // same as symbol in ERC20
        string name; // full name of token
        uint256 cap; // Hard cap of token
        uint256 limitPerMint; // Limitation per mint
        uint256 maxMintSize; // // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint
        uint256 inscriptionId; // Inscription id
        uint256 freezeTime;
        address onlyContractAddress;
        uint256 onlyMinQuantity;
        uint256 crowdFundingRate;
        address crowdfundingAddress;
        address addr; // Contract address of inscribed token
        uint256 timestamp; // Inscribe timestamp
    }

    constructor() {
        // The inscription id will be from 1, not zero.
        _inscriptionNumbers.increment();
    }

    // Let this contract accept ETH as tip
    receive() external payable {}

    function deploy(
        string memory _name,
        string memory _tick,
        uint256 _cap,
        uint256 _limitPerMint,
        uint256 _maxMintSize, // The max lots of each mint
        uint256 _freezeTime, // Freeze seconds between two mint, during this freezing period, the mint fee will be increased
        address _onlyContractAddress, // Only the holder of this asset can mint, optional
        uint256 _onlyMinQuantity, // The min quantity of asset for mint, optional
        uint256 _crowdFundingRate,
        address _crowdFundingAddress,
        bool _isBurnPlatform
    ) external returns (address _inscriptionAddress) {
        // require(String.strlen(_tick) == maxTickSize, "Tick lenght should be 4");
        require(_cap >= _limitPerMint, "Limit per mint exceed cap");

        _tick = String.toLower(_tick);

        require(!_compare(_tick, "mint"), "tickcannot use mint");
        require(!_compare(_tick, "mints"), "tickcannot use mints");
        require(!_compare(_tick, "blockmint"), "tickcannot use blockmint");
        require(!_compare(_tick, "blockmints"), "tickcannot use blockmints");

        require(this.getIncriptionIdByTick(_tick) == 0, "tick is existed");

        // Check platform asset
        require(
            platformAddress == address(0x0) ||
                ICommonToken(platformAddress).balanceOf(msg.sender) >=
                platformDeployQuantity,
            "You don't have required MINT assets"
        );

        // Create inscription contract
        bytes memory bytecode = type(Inscription).creationCode;
        uint256 _id = _inscriptionNumbers.current();
        bytes32 _salt = keccak256(abi.encodePacked(_id));

        bytecode = abi.encodePacked(
            bytecode,
            abi.encode(
                _name,
                _tick,
                _cap,
                _limitPerMint,
                _id,
                _maxMintSize,
                _freezeTime,
                _onlyContractAddress,
                _onlyMinQuantity,
                baseFee,
                fundingCommission,
                _crowdFundingRate,
                _crowdFundingAddress,
                address(this),
                platformAddress,
                platformMinQuantity,
                _isBurnPlatform ? mintBurnPlatformQuantity : 0
            )
        );

        assembly ("memory-safe") {
            _inscriptionAddress := create2(
                0,
                add(bytecode, 32),
                mload(bytecode),
                _salt
            )
            if iszero(extcodesize(_inscriptionAddress)) {
                revert(0, 0)
            }
        }
        inscriptions[_id] = Token(
            _tick,
            _name,
            _cap,
            _limitPerMint,
            _maxMintSize,
            _id,
            _freezeTime,
            _onlyContractAddress,
            _onlyMinQuantity,
            _crowdFundingRate,
            _crowdFundingAddress,
            _inscriptionAddress,
            block.timestamp
        );
        ticks[_tick] = _id;

        _inscriptionNumbers.increment();
        emit DeployInscription(
            _id,
            _tick,
            _name,
            _cap,
            _limitPerMint,
            _inscriptionAddress,
            block.timestamp
        );
    }

    function getInscriptionAmount() external view returns (uint256) {
        return _inscriptionNumbers.current() - 1;
    }

    function getIncriptionIdByTick(
        string memory _tick
    ) external view returns (uint256) {
        return ticks[String.toLower(_tick)];
    }

    function getIncriptionById(
        uint256 _id
    ) external view returns (Token memory, uint256) {
        Token memory token = inscriptions[_id];
        return (inscriptions[_id], Inscription(token.addr).totalSupply());
    }

    function getIncriptionByTick(
        string memory _tick
    ) external view returns (Token memory, uint256) {
        Token memory token = inscriptions[this.getIncriptionIdByTick(_tick)];
        return (
            inscriptions[this.getIncriptionIdByTick(_tick)],
            Inscription(token.addr).totalSupply()
        );
    }

    function getInscriptionAmountByType(
        uint256 _type
    ) external view returns (uint256) {
        require(_type < 3, "type is 0-2");
        uint256 totalInscription = this.getInscriptionAmount();
        uint256 count = 0;
        for (uint256 i = 1; i <= totalInscription; i++) {
            (Token memory _token, uint256 _totalSupply) = this
                .getIncriptionById(i);
            if (_type == 1 && _totalSupply == _token.cap) continue;
            else if (_type == 2 && _totalSupply < _token.cap) continue;
            else count++;
        }
        return count;
    }

    // Fetch inscription data by page no, page size, type and search keyword
    function getIncriptions(
        uint256 _pageNo,
        uint256 _pageSize,
        uint256 _type, // 0- all, 1- in-process, 2- ended
        string memory _searchBy
    )
        external
        view
        returns (Token[] memory inscriptions_, uint256[] memory totalSupplies_)
    {
        // if _searchBy is not empty, the _pageNo and _pageSize should be set to 1
        require(_type < 3, "type is 0-2");
        uint256 totalInscription = this.getInscriptionAmount();
        uint256 pages = (totalInscription - 1) / _pageSize + 1;
        require(
            _pageNo > 0 && _pageSize > 0 && pages > 0 && _pageNo <= pages,
            "Params wrong"
        );

        inscriptions_ = new Token[](_pageSize);
        totalSupplies_ = new uint256[](_pageSize);

        Token[] memory _inscriptions = new Token[](totalInscription);
        uint256[] memory _totalSupplies = new uint256[](totalInscription);

        uint256 index = 0;
        for (uint256 i = 1; i <= totalInscription; i++) {
            (Token memory _token, uint256 _totalSupply) = this
                .getIncriptionById(i);
            if (_type == 1 && _totalSupply == _token.cap) continue;
            else if (_type == 2 && _totalSupply < _token.cap) continue;
            else if (
                !String.compareStrings(_searchBy, "") &&
                !String.compareStrings(String.toLower(_searchBy), _token.tick)
            ) continue;
            else {
                _inscriptions[index] = _token;
                _totalSupplies[index] = _totalSupply;
                index++;
            }
        }

        for (uint256 i = 0; i < _pageSize; i++) {
            uint256 id = (_pageNo - 1) * _pageSize + i;
            if (id < index) {
                inscriptions_[i] = _inscriptions[id];
                totalSupplies_[i] = _totalSupplies[id];
            }
        }
    }

    function _compare(
        string memory str1,
        string memory str2
    ) internal pure returns (bool) {
        return keccak256(bytes(str1)) == keccak256(bytes(str2));
    }

    // Withdraw the ETH tip from the contract
    function withdraw(address payable _to, uint256 _amount) external onlyOwner {
        require(_amount <= payable(address(this)).balance);
        TransferHelper.safeTransferETH(_to, _amount);
    }

    // Update base fee
    function updateBaseFee(uint256 _fee) external onlyOwner {
        baseFee = _fee;
    }

    // Update funding commission
    function updateFundingCommission(uint256 _rate) external onlyOwner {
        fundingCommission = _rate;
    }

    // Update character's length of tick
    function updateTickSize(uint8 _size) external onlyOwner {
        maxTickSize = _size;
    }

    // set platform
    function updatePlatformAddress(address _pfAddress) external onlyOwner {
        platformAddress = _pfAddress;
    }

    // set platformMinQuantity
    function updatePlatformMinQuantity(
        uint256 _minQuantity
    ) external onlyOwner {
        platformMinQuantity = _minQuantity;
    }

    // set deploy platformMinQuantity
    function updatePlatformDeployQuantity(
        uint256 _quantity
    ) external onlyOwner {
        platformDeployQuantity = _quantity;
    }

}

