pragma solidity 0.8.10;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ReactorV1 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
	using SafeMathUpgradeable for uint256;
	using SafeERC20Upgradeable for IERC20Upgradeable;
	IERC20Upgradeable public stakedToken;

	struct Project {
		string repoType;
		string repoUserName;
		string repo;
		string branch;
		address owner;
		bool verified;
		mapping(address => bool) maintainers;
	}
	mapping(uint => Project) public projectMap;
	uint public projectCount;
	mapping(address => uint256) public userStake;
	mapping(address => uint) public userProjectCount;
	uint256 public stakedAmountPerProject;
	uint256 public payPerAction;
	uint256 public totalPayout;

	modifier onlyProjectOwner(uint _projectId) {
		require(projectMap[_projectId].owner == msg.sender, "Only project owner can perform this action");
		_;
	}

	function initialize(IERC20Upgradeable _stakedToken, uint256 _stakedAmountPerProject) external initializer {
		stakedToken = _stakedToken;
		stakedAmountPerProject = _stakedAmountPerProject;
		__Ownable_init();
		__ReentrancyGuard_init();
	}
	event ProjectAdded(uint indexed projectId, address indexed owner, string repoType, string repoUserName, string repo, string branch);
	event MaintainerAdded(address indexed maintainer, uint indexed projectId);
	event MaintainerRemoved(address indexed maintainer, uint indexed projectId);
	event ProjectOwnerChanged(address indexed oldOwner, address indexed newOwner, uint indexed projectId);
	event ProjectVerified(uint indexed projectId, bool verified);
	event StakedTokenChanged(IERC20Upgradeable indexed oldToken, IERC20Upgradeable indexed newToken);
	event StakedAmountPerProjectChanged(uint256 indexed oldAmount, uint256 indexed newAmount);
	event Stake(address indexed user, uint256 amount);
	event Unstake(address indexed user, uint256 amount);
	event ProjectDetailsChanged(uint indexed projectId, string repoType, string repoUserName, string repo, string branch);
	event PayPerActionChanged(uint256 indexed oldAmount, uint256 indexed newAmount);
	event Action(address indexed user, uint indexed projectId, uint indexed actionType, uint256 amount, uint256 timestamp);

	function doAction(uint _projectId, uint _action, address _user) private {
		if (payPerAction == 0) {
			return ;
		} else {
			stakedToken.safeTransferFrom(msg.sender, address(this), payPerAction);
			totalPayout = totalPayout.add(payPerAction);
			emit Action(_user, _projectId, _action, payPerAction, block.timestamp);
		}
	}

	function addProject(string memory _repoType, string memory _repoUserName, string memory _repo, string memory _branch) external nonReentrant returns(uint) {
		require(userStake[msg.sender].sub(stakedAmountPerProject.mul(userProjectCount[msg.sender])) >= stakedAmountPerProject, "Not enough staked amount");
		uint projectId = projectCount;
		projectMap[projectId].repoType = _repoType;
		projectMap[projectId].repoUserName = _repoUserName;
		projectMap[projectId].repo = _repo;
		projectMap[projectId].branch = _branch;
		projectMap[projectId].owner = msg.sender;
		projectMap[projectId].verified = false;
		projectMap[projectId].maintainers[msg.sender] = true;
		projectCount++;
		userProjectCount[msg.sender]++;
		doAction(projectId, 1, msg.sender);
		emit ProjectAdded(projectId, msg.sender, _repoType, _repoUserName, _repo, _branch);
		return projectId;
	}

	function addMaintainer(uint _projectId, address _maintainer) external onlyProjectOwner(_projectId) {
		require(!projectMap[_projectId].maintainers[_maintainer], "Maintainer already exists");
		require(userStake[_maintainer].sub(stakedAmountPerProject.mul(userProjectCount[_maintainer])) >= stakedAmountPerProject, "Not enough staked amount");
		projectMap[_projectId].maintainers[_maintainer] = true;
		userProjectCount[_maintainer]++;
		emit MaintainerAdded(_maintainer, _projectId);
	}

	function removeMaintainer(uint _projectId, address _maintainer) external {
		require(projectMap[_projectId].maintainers[_maintainer], "Maintainer does not exist");
		require(msg.sender == _maintainer || msg.sender == projectMap[_projectId].owner, "Only project owner or maintainer can remove a maintainer");
		projectMap[_projectId].maintainers[_maintainer] = false;
		userProjectCount[_maintainer]--;
		emit MaintainerRemoved(_maintainer, _projectId);
	}

	function changeProjectOwner(uint _projectId, address _newOwner) external onlyProjectOwner(_projectId) {
		require(_newOwner != address(0), "New owner cannot be the zero address");
		require(projectMap[_projectId].maintainers[_newOwner], "New owner must be a maintainer");
		projectMap[_projectId].owner = _newOwner;
		emit ProjectOwnerChanged(projectMap[_projectId].owner, _newOwner, _projectId);
	}

	function isMaintainer(uint _projectId, address _user) external view returns(bool) {
		return projectMap[_projectId].maintainers[_user];
	}

	function stake(uint256 _amount) external nonReentrant {
		stakedToken.safeTransferFrom(msg.sender, address(this), _amount);
		userStake[msg.sender] = userStake[msg.sender].add(_amount);
		emit Stake(msg.sender, _amount);
	}

	function unstake(uint256 _amount) external nonReentrant {
		stakedToken.safeTransfer(msg.sender, _amount);
		userStake[msg.sender] = userStake[msg.sender].sub(_amount);
		emit Unstake(msg.sender, _amount);
	}

	function verifyProject(uint _projectId) external onlyOwner {
		projectMap[_projectId].verified = true;
		emit ProjectVerified(_projectId, true);
	}

	function unverifyProject(uint _projectId) external onlyOwner {
		projectMap[_projectId].verified = false;
		emit ProjectVerified(_projectId, false);
	}

	function changeStakedToken(IERC20Upgradeable _newStakedToken) external onlyOwner {
		stakedToken = _newStakedToken;
		emit StakedTokenChanged(stakedToken, _newStakedToken);
	}

	function changeStakedAmountPerProject(uint256 _amount) external onlyOwner {
		stakedAmountPerProject = _amount;
		emit StakedAmountPerProjectChanged(stakedAmountPerProject, _amount);
	}

	function changePayPerAction(uint256 _amount) external onlyOwner {
		payPerAction = _amount;
		emit PayPerActionChanged(payPerAction, _amount);
	}

	function action(uint _projectId, uint _action) external {
		require(projectMap[_projectId].maintainers[msg.sender], "Only maintainers can perform actions");
		doAction(_projectId, _action, msg.sender);
	}

	function changeProjectDetails(uint _projectId, string memory _repoType, string memory _repoUserName, string memory _repo, string memory _branch) external onlyProjectOwner(_projectId) {
		projectMap[_projectId].repoType = _repoType;
		projectMap[_projectId].repoUserName = _repoUserName;
		projectMap[_projectId].repo = _repo;
		projectMap[_projectId].branch = _branch;
		emit ProjectDetailsChanged(_projectId, _repoType, _repoUserName, _repo, _branch);
	}
}