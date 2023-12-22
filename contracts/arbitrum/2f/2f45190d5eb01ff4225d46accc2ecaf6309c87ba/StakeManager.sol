// SPDX-License-Identifier: MIT LICENSE
pragma solidity >0.8.0;
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";

import "./IStakeManager.sol";
import "./StakeManagerBase.sol";
import "./IPeekABoo.sol";

contract StakeManager is
    Initializable,
    IStakeManager,
    ERC721HolderUpgradeable,
    OwnableUpgradeable,
    StakeManagerBase
{
    function initialize(
        address[] memory _services,
        string[] memory _serviceNames
    ) public initializer {
        __ERC721Holder_init();
        __Ownable_init();
        for (uint256 i = 0; i < _services.length; i++) {
            addService(_services[i], _serviceNames[i]);
        }
    }

    modifier onlyService() {
        bool _isService = false;
        for (uint256 i; i < services.length; i++) {
            if (msg.sender == services[i]) {
                _isService = true;
            }
        }
        require(
            _isService,
            "You're not an authorized staking service, you can't make changes."
        );
        _;
    }

    modifier onlyPeekABoo() {
        require(
            msg.sender == address(peekaboo),
            "Only the IPeekABoo contract can call this function"
        );
        _;
    }

    function addService(address service, string memory serviceName)
        public
        onlyOwner
    {
        serviceAddressToIndex[service] = services.length;
        stakeServiceToServiceName[service] = serviceName;
        services.push(service);
    }

    function removeService(address service) external onlyOwner {
        require(services.length > 0, "no services to remove");
        uint256 toRemoveIndex = serviceAddressToIndex[service];
        require(
            services[toRemoveIndex] == service,
            "StakeManager: Service is not in array."
        );
        address toRemove = services[toRemoveIndex];
        address _temp = services[services.length - 1];

        services[services.length - 1] = toRemove;
        services[toRemoveIndex] = _temp;

        serviceAddressToIndex[_temp] = toRemoveIndex;
        delete serviceAddressToIndex[service];
        delete stakeServiceToServiceName[service];
        services.pop();
    }

    function stakePABOnService(
        uint256 tokenId,
        address service,
        address owner
    ) external onlyService {
        require(peekaboo.ownerOf(tokenId) == owner, "This isn't your token");
        peekaboo.safeTransferFrom(owner, address(this), tokenId);
        tokenIdToStakeService[tokenId] = service;
        tokenIdToOwner[tokenId] = owner;
        ownerToTokens[owner].push(tokenId);
    }

    function isStaked(uint256 tokenId, address service)
        external
        view
        returns (bool)
    {
        return tokenIdToStakeService[tokenId] == service;
    }

    function unstakePeekABoo(uint256 tokenId) external onlyService {
        address _owner = tokenIdToOwner[tokenId];
        peekaboo.safeTransferFrom(address(this), _owner, tokenId);
        tokenIdToStakeService[tokenId] = address(0);
        tokenIdToOwner[tokenId] = address(0);

        for (uint256 i = 0; i < ownerToTokens[_owner].length; i++) {
            if (ownerToTokens[_owner][i] == tokenId) {
                ownerToTokens[_owner][i] = ownerToTokens[_owner][
                    ownerToTokens[_owner].length - 1
                ];
                ownerToTokens[_owner].pop();
            }
        }
    }

    function getServices() external view returns (address[] memory) {
        return services;
    }

    function isService(address service) external view returns (bool) {
        return (keccak256(
            abi.encodePacked(stakeServiceToServiceName[service])
        ) != keccak256(abi.encodePacked("")));
    }

    function initializeEnergy(uint256 tokenId) external onlyPeekABoo {
        tokenIdToEnergy[tokenId] = 12;
        tokenIdToClaimtime[tokenId] = block.timestamp;
    }

    function claimEnergy(uint256 tokenId) external {
        uint256 claimable = claimableEnergy(tokenId);
        if (claimable > 0) {
            uint256 carryOver = carryOverTime(tokenId);
            tokenIdToEnergy[tokenId] += claimable;
            tokenIdToClaimtime[tokenId] = block.timestamp - carryOver;
            if (tokenIdToEnergy[tokenId] > 12) tokenIdToEnergy[tokenId] = 12;
        }
    }

    function claimableEnergy(uint256 tokenId) public view returns (uint256) {
        return (block.timestamp - tokenIdToClaimtime[tokenId]) / 2 hours;
    }

    function carryOverTime(uint256 tokenId) public view returns (uint256) {
        return (block.timestamp - tokenIdToClaimtime[tokenId]) % 2 hours;
    }

    function hasEnergy(uint256 tokenId, uint256 amount)
        public
        view
        returns (bool)
    {
        return tokenIdToEnergy[tokenId] >= amount;
    }

    function getEnergyAmount(uint256 tokenId) public view returns (uint256) {
        return tokenIdToEnergy[tokenId];
    }

    function useEnergy(uint256 tokenId, uint256 amount) external onlyService {
        require(hasEnergy(tokenId, amount), "No energy");
        tokenIdToEnergy[tokenId] -= amount;
    }

    function setPeekABoo(address _peekaboo) external onlyOwner {
        peekaboo = IPeekABoo(_peekaboo);
    }

    function ownerOf(uint256 tokenId) external returns (address) {
        return tokenIdToOwner[tokenId];
    }

    function tokensOf(address owner) external returns (uint256[] memory) {
        return ownerToTokens[owner];
    }
}

