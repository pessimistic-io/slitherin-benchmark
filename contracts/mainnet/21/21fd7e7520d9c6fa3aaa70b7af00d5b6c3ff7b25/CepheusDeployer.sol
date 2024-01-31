// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

interface GeneralInterface {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external;

    function burn(uint256 amount) external;

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function cap() external view returns (uint256);

    function getTaxesAndAddress()
        external
        view
        returns (uint256[] memory, address[] memory);

    function getDiflationPercent() external view returns (uint256);

    function getReflexRate() external view returns (uint256);
}

contract CepheusDeployer is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private _chainId;

    struct ContractData {
        address deployer;
        address contractAddress;
        uint256 chainId;
        uint256 contractIndex;
        string contractName;
        bool mintable;
        bool burnable;
        bool capped;
        bool role;
        bool baseURI;
    }

    mapping(uint256 => mapping(address => uint256)) private _userTotalContract;

    mapping(uint256 => mapping(address => mapping(uint256 => ContractData)))
        private _indexToContract;

    mapping(uint256 => uint256) private _contractToPrice;

    address private _collectorAddress;

    GeneralInterface private _token;

    function initialize(
        uint256 chainId,
        address tokenAddress,
        address collectorAddress,
        uint256[] memory contractTypes,
        uint256[] memory prices
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        _chainId = chainId;
        _token = GeneralInterface(tokenAddress);
        _collectorAddress = collectorAddress;
        uint256 length = contractTypes.length;
        require(length == prices.length);
        for (uint256 i; i < length; i++) {
            _contractToPrice[contractTypes[i]] = prices[i];
        }
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function getChainId() external view returns (uint256) {
        return _chainId;
    }

    function getDeploymentPrice(uint256 howManyTokensPrice)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory contractPrice = new uint256[](howManyTokensPrice);

        for (uint256 i = 1; i <= howManyTokensPrice; i++) {
            contractPrice[i - 1] = _contractToPrice[i];
        }
        return contractPrice;
    }

    function getCollectorAddress() external view returns (address) {
        return _collectorAddress;
    }

    function getTokenAddress() external view returns (address) {
        return address(_token);
    }

    function getUserContracts(address deployer)
        external
        view
        returns (
            ContractData[] memory,
            ContractData[] memory,
            ContractData[] memory,
            ContractData[] memory,
            ContractData[] memory,
            ContractData[] memory
        )
    {
        return (
            _getAllContractDetails(1, deployer),
            _getAllContractDetails(2, deployer),
            _getAllContractDetails(3, deployer),
            _getAllContractDetails(4, deployer),
            _getAllContractDetails(5, deployer),
            _getAllContractDetails(6, deployer)
        );
    }

    function _getAllContractDetails(uint8 contractType, address deployer)
        internal
        view
        returns (ContractData[] memory)
    {
        uint256 length = _userTotalContract[contractType][deployer];
        ContractData[] memory allContracts = new ContractData[](length);
        for (uint256 i; i < length; i++) {
            allContracts[i] = _indexToContract[contractType][deployer][i];
        }
        return allContracts;
    }

    function getNFTContractByUserAndIndex(
        address user,
        uint256 index,
        uint8 contractType
    )
        external
        view
        returns (
            ContractData memory,
            string memory,
            string memory,
            uint256
        )
    {
        address contractAddress = _indexToContract[contractType][user][index]
            .contractAddress;
        GeneralInterface token = GeneralInterface(contractAddress);
        return (
            _indexToContract[contractType][user][index],
            token.name(),
            token.symbol(),
            token.totalSupply()
        );
    }

    function getContractByUserAndIndex(
        address user,
        uint256 index,
        uint8 contractType,
        bool[4] memory conditions
    )
        external
        view
        returns (
            ContractData memory,
            string memory,
            string memory,
            uint8,
            uint256,
            uint256[] memory
        )
    {
        uint256[] memory amounts = new uint256[](3);

        address contractAddress = _indexToContract[contractType][user][index]
            .contractAddress;
        GeneralInterface token = GeneralInterface(contractAddress);
        if (conditions[0]) {
            amounts[0] = token.cap();
        }

        if (conditions[2]) {
            amounts[1] = token.getDiflationPercent();
        }

        if (conditions[3]) {
            amounts[2] = token.getReflexRate();
        }
        return (
            _indexToContract[contractType][user][index],
            token.name(),
            token.symbol(),
            token.decimals(),
            token.totalSupply(),
            amounts
        );
    }

    function transferDeployerOwnership(
        uint8 contractType,
        address contractAddress,
        address deployer,
        address newDeployer,
        uint256 index
    ) external {
        require(msg.sender == deployer, "Address is not the owner of contract");
        require(deployer != newDeployer, "Transfering to self");
        require(newDeployer != address(0), "Could not send to zero Address");
        require(
            _indexToContract[contractType][deployer][index].contractAddress ==
                contractAddress,
            "Invalid Contract at index"
        );
        uint256 newIndex = _userTotalContract[contractType][newDeployer];
        _indexToContract[contractType][newDeployer][
            newIndex
        ] = _indexToContract[contractType][deployer][index];

        _indexToContract[contractType][newDeployer][newIndex]
            .deployer = newDeployer;

        _indexToContract[contractType][newDeployer][newIndex]
            .contractIndex = newIndex;

        _userTotalContract[contractType][newDeployer]++;

        uint256 lastIndex = _userTotalContract[contractType][deployer] - 1;
        if (index != lastIndex) {
            _indexToContract[contractType][deployer][index] = _indexToContract[
                contractType
            ][deployer][lastIndex];
        }
        delete _indexToContract[contractType][deployer][lastIndex];
        _userTotalContract[contractType][deployer]--;
    }

    function deploy(
        bytes memory bytecode,
        bytes memory constructorArgs,
        address deployer,
        string memory contractName,
        uint8 contractType,
        uint256 amount,
        bool mintable,
        bool burnable,
        bool capped,
        bool role,
        bool baseURI
    ) external returns (address addr) {
        require(amount == _contractToPrice[contractType], "Invalid price");
        _token.transferFrom(msg.sender, _collectorAddress, amount);

        bytes memory _bytecode = abi.encodePacked(bytecode, constructorArgs);
        assembly {
            addr := create(0, add(_bytecode, 0x20), mload(_bytecode))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        _updateDataOfdeployer(
            deployer,
            contractName,
            contractType,
            addr,
            mintable,
            burnable,
            capped,
            role,
            baseURI
        );
    }

    function _updateDataOfdeployer(
        address deployer,
        string memory contractName,
        uint8 contractType,
        address contractAddress,
        bool mintable,
        bool burnable,
        bool capped,
        bool role,
        bool baseURI
    ) internal {
        uint256 index = _userTotalContract[contractType][deployer];
        ContractData memory contractData = ContractData(
            deployer,
            contractAddress,
            _chainId,
            index,
            contractName,
            mintable,
            burnable,
            capped,
            role,
            baseURI
        );

        _indexToContract[contractType][deployer][index] = contractData;
        _userTotalContract[contractType][deployer]++;
    }

    function setChainId(uint256 chainId) external onlyOwner {
        _chainId = chainId;
    }

    function setPriceOfContractType(uint256 contractType, uint256 price)
        external
        onlyOwner
    {
        _contractToPrice[contractType] = price;
    }

    function setCollectorAddress(address collectorAddress) external onlyOwner {
        _collectorAddress = collectorAddress;
    }

    function setTokenAddress(address tokenAddress) external onlyOwner {
        _token = GeneralInterface(tokenAddress);
    }

    function setNewContractOfDeployer(
        address deployer,
        address contractAddress,
        string memory contractName,
        uint8 contractType,
        bool mintable,
        bool burnable,
        bool capped,
        bool role,
        bool baseURI
    ) external onlyOwner {
        _updateDataOfdeployer(
            deployer,
            contractName,
            contractType,
            contractAddress,
            mintable,
            burnable,
            capped,
            role,
            baseURI
        );
    }
}

