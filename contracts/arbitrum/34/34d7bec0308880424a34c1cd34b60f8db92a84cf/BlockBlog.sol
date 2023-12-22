pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";

contract BlockBlog is ERC20Upgradeable {
	// blog
	enum BlogType {
		New,
		Comment,
		Retweet
	}
	struct Blog {
		address Author;
		uint Influential;
		uint EntryIndex;
		uint Like;
		BlogType BlogType;
		uint FatherBlogIndex;
		uint[] ChildBlogIndex;
		string Content;
		uint TimeStamp;
	}

	Blog[] public Blogs; // The first one has no entry

	// entry
	struct Entry {
		string EntryWord;
		uint[] Blogs;
		uint Influential;
	}

	Entry[] public Entries;

	// user
	struct User {
		address[] Following;// fan
		address[] Follower;
		uint[] Blogs;
		uint Influential;
	}

	struct UserReturn {
		uint FollowingLength;
		uint FollowerLength;
		uint BlogsLength;
		uint Influential;
	}

	event PublishBlog(uint,address,uint);
	event Like(address,uint);
	event Following(address,address,bool);

	mapping(address => User) Users;

	address public gov;
	address public FeeAddress;
	uint public PublishBlogFee;
	uint public MinPublicBlogInfluential;

	uint8 constant decimalsPRECISION = 8;
	uint constant PRECISION = 10**decimalsPRECISION;

	function initialize(
		string memory _name,
		string memory _symbol,
		uint256 initialSupply,
		address _gov,
		address _feeAddress
	) external initializer {
		require(
			_feeAddress != address(0)
			&& _gov != address(0)
		);

		__ERC20_init(_name, _symbol);

		_mint(msg.sender, initialSupply);

		gov = _gov;
		PublishBlogFee = PRECISION * 10;
		MinPublicBlogInfluential = PRECISION * 10;
		FeeAddress = _feeAddress;

		// Create an Untitled Blog Post
		publishBlog("", BlogType.New, "For Freedom", 0, 0);
	}

	modifier onlyGov(){
		require(msg.sender == gov, "GOV_ONLY");
		_;
	}

	function decimals() public pure override returns (uint8) {
		return decimalsPRECISION;
	}

	function updatePublishBlogFee(uint _PublishBlogFee) external onlyGov {
		require(_PublishBlogFee > 0, "_PublishBlogFee err");
		PublishBlogFee = _PublishBlogFee;
	}

	function updateMinPublicBlogInfluential(uint _MinPublicBlogInfluential) external onlyGov {
		require(_MinPublicBlogInfluential > 0, "_MinPublicBlogInfluential err");
		MinPublicBlogInfluential = _MinPublicBlogInfluential;
	}

	function updateFeeAddress(address _FeeAddress) external onlyGov {
		require(_FeeAddress != address(0), "_FeeAddress err");
		FeeAddress = _FeeAddress;
	}

    function getEntryBlogIndex(uint index, uint blogIndex) public view returns (uint){
        require(index < Entries.length, "index err");
        require(blogIndex < Entries[index].Blogs.length, "blogIndex err");

        return Entries[index].Blogs[blogIndex];
    }

    function getBlogChildIndexTen(uint index, uint childIndex) public view returns (uint){
        require(index < Blogs.length, "index err");
        require(childIndex < Blogs[index].ChildBlogIndex.length, "childIndex err");

        return Blogs[index].ChildBlogIndex[childIndex];
    }

	function getUser(address addr) public view returns (UserReturn memory){
		UserReturn memory userReturn = UserReturn(
			Users[addr].Following.length,
			Users[addr].Follower.length,
			Users[addr].Blogs.length,
			Users[addr].Influential);
		return userReturn;
	}

	function getUserFollowingByIndex(address addr, uint index) public view returns (address){
		require(index < Users[addr].Following.length, "index err");

		return Users[addr].Following[index];
	}

	function getUserFollowerByIndex(address addr, uint index) public view returns (address){
		require(index < Users[addr].Follower.length, "index err");

		return Users[addr].Follower[index];
	}

	function getUserBlogByIndex(address addr, uint index) public view returns (uint){
		require(index < Users[addr].Blogs.length, "index err");

		return Users[addr].Blogs[index];
	}

	function following(address addr) public {
		require(!isFollowing(msg.sender,addr),"Following err");
		require(msg.sender != addr,"cant not Following yourself");

		Users[msg.sender].Following.push(addr);
		Users[addr].Follower.push(msg.sender);
		emit Following(msg.sender,addr,true);
	}
	function unFollowing(address addr) public {
		bool isExist = false;
		for(uint i=0;i<Users[msg.sender].Following.length;i++){
			if(addr == Users[msg.sender].Following[i]){
				Users[msg.sender].Following[i] = Users[msg.sender].Following[Users[msg.sender].Following.length-1];
				delete Users[msg.sender].Following[Users[msg.sender].Following.length-1];
				isExist=true;
				break;
			}
		}
		require(isExist,"not found Following");
		isExist = false;

		for(uint i=0;i<Users[addr].Follower.length;i++){
			if(msg.sender == Users[addr].Follower[i]){
				Users[addr].Follower[i] = Users[addr].Follower[Users[addr].Follower.length-1];
				delete Users[addr].Follower[Users[addr].Follower.length-1];
				isExist=true;
				break;
			}
		}
		require(isExist,"not found Follower");
		emit Following(msg.sender,addr,false);
	}
	function isFollowing (address from,address addr) public view returns(bool) {
		for(uint i = 0;i<Users[from].Following.length;i++){
			if(Users[from].Following[i]==addr){
				return true;
			}
		}
		return false;
	}

	function like(uint blogIndex) public {
		require(blogIndex < Blogs.length, "blog err");

		uint maxCoin = 5 * PRECISION;
		uint feeCoin = 3 * PRECISION;
		Blogs[blogIndex].Like += 1;

		uint flagIndex = blogIndex;
		for (uint i = 0; i < type(uint).max; i++) {
			Blogs[flagIndex].Influential += maxCoin;
			if (Blogs[flagIndex].BlogType == BlogType.New) {
				break;
			}
			flagIndex = Blogs[flagIndex].FatherBlogIndex;
		}

		Entries[Blogs[blogIndex].EntryIndex].Influential += maxCoin;
		Users[Blogs[blogIndex].Author].Influential += maxCoin;

		transfer(FeeAddress, feeCoin);
		transfer(Blogs[blogIndex].Author, maxCoin - feeCoin);
		emit Like(msg.sender,blogIndex);
	}

	function publishBlog(string memory entryWord, BlogType blogType, string memory content, uint Influential, uint FatherBlogIndex) public {
		require(Influential + PublishBlogFee <= balanceOf(msg.sender),"Insufficient quantity");
		require(Influential % PublishBlogFee == 0,"Influential err");

		if (blogType != BlogType.New && FatherBlogIndex == 0) {
			revert("not new blog need father blog");
		}
		if (blogType == BlogType.New && Influential != 0) {
			revert("the new blog not need extra fee");
		}
		if (blogType != BlogType.New && keccak256(abi.encodePacked(entryWord)) != keccak256(abi.encodePacked(""))) {
			revert("not new blog has entry");
		}
		if (blogType != BlogType.New && Influential < MinPublicBlogInfluential) {
			revert("coin count err");
		}
		if (FatherBlogIndex != 0 && FatherBlogIndex >= Blogs.length) {
			revert("father blog err");
		}

		address author = msg.sender;

		// 创建博文
		uint blogIndex = Blogs.length;
		uint[] memory ChildBlogs;
		Blogs.push(Blog(author, PublishBlogFee + Influential, 0, 0, blogType, 0, ChildBlogs, content, block.timestamp));


		// find entry
		uint entryIndex = 0;
		if (blogType != BlogType.New) {
			// Comment,Retweet
			entryIndex = Blogs[FatherBlogIndex].EntryIndex;
			Entries[entryIndex].Influential += Blogs[blogIndex].Influential;
			Blogs[blogIndex].FatherBlogIndex = FatherBlogIndex;
			Users[Blogs[FatherBlogIndex].Author].Influential += Blogs[blogIndex].Influential;
		} else {
			uint i;
			for (i = 0; i < Entries.length; i++) {
				if (keccak256(abi.encodePacked(entryWord)) == keccak256(abi.encodePacked(Entries[i].EntryWord))) {
					break;
				}
			}

			if (i == Entries.length) {
				// new entry
				entryIndex = Entries.length;
				uint[] memory EntryBlogs;
				Entries.push(Entry(entryWord, EntryBlogs, Blogs[blogIndex].Influential));
				Entries[Entries.length - 1].Blogs.push(blogIndex);
				Users[author].Influential += Blogs[blogIndex].Influential;
			} else {
				// has entry
				entryIndex = i;
				Entries[i].Influential += PublishBlogFee + Influential;
				Entries[entryIndex].Blogs.push(blogIndex);
				Users[author].Influential += Blogs[blogIndex].Influential;
			}
		}
		Blogs[blogIndex].EntryIndex = entryIndex;

		// Record user information
		Users[author].Blogs.push(blogIndex);

		// Influential
		uint mainBlogIndex = 0;
		if (blogType != BlogType.New) {
			// father blog add child blog index
			Blogs[Blogs[blogIndex].FatherBlogIndex].ChildBlogIndex.push(blogIndex);

			// myself and ancestors add Influential
			uint flagIndex = Blogs[blogIndex].FatherBlogIndex;
			for (uint i = 0; i < type(uint).max; i++) {
				Blogs[flagIndex].Influential += PublishBlogFee + Influential;
				if (Blogs[flagIndex].BlogType == BlogType.New) {
					mainBlogIndex = flagIndex;
					break;
				}
				flagIndex = Blogs[flagIndex].FatherBlogIndex;
			}
		}

		// transfer token
		// base fee4766

		transfer(FeeAddress, PublishBlogFee);
		if (blogType != BlogType.New) {
			// 30% to target，20% to source
			uint fatherFee = uint((int(Influential) * 3) / 10);
			uint mainFee = uint((int(Influential) * 2) / 10);
			uint fee = uint(int(Influential) - int(fatherFee) - int(mainFee));

			transfer(Blogs[FatherBlogIndex].Author, fatherFee);
			transfer(Blogs[mainBlogIndex].Author, mainFee);
			transfer(FeeAddress, fee);
		}

		emit PublishBlog(blogIndex,msg.sender,Influential);
	}
}
