// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ConfigurableStateMachine
 * @dev Implementação de uma máquina de estados configurável para contratos inteligentes
 * com suporte a integração com verificadores ZKP
 */
contract ConfigurableStateMachine {
    
    struct State {
        bytes32 id;
        string name;
        string description;
        bool isFinal;
        bool isError;
        bytes32[] onEnterActions;
        bytes32[] onExitActions;
    }
       
    struct Transition {
        bytes32 id;
        string name;
        string description;
        bytes32 fromState;
        bytes32 toState;
        bytes32[] conditions;
        bytes32[] actions;
    }
    
    struct TransitionEvent {
        uint256 timestamp;
        bytes32 fromState;
        bytes32 toState;
        bytes32 transitionId;
    }
    
    bytes32 public id;
    string public name;
    string public description;
    bytes32 public initialState;
    bytes32 public currentState;
    
    mapping(bytes32 => State) public states;
    mapping(bytes32 => Transition[]) public stateTransitions;
    mapping(bytes32 => Transition) public transitions;
    mapping(bytes32 => address) public conditionVerifiers;
    mapping(bytes32 => address) public actionExecutors;
    
    bytes32[] public stateHistory;
    TransitionEvent[] public transitionHistory;
    
    event StateChanged(bytes32 indexed fromState, bytes32 indexed toState, bytes32 indexed transitionId);
    event ConditionFailed(bytes32 indexed transitionId, bytes32 indexed conditionId, string reason);
    event ActionExecuted(bytes32 indexed transitionId, bytes32 indexed actionId, bool success);
    event StateMachineInitialized(bytes32 indexed id, bytes32 indexed initialState);
    
    modifier onlyExistingState(bytes32 stateId) {
        require(states[stateId].id == stateId, "Estado nao existe");
        _;
    }
    
    modifier onlyExistingTransition(bytes32 transitionId) {
        require(transitions[transitionId].id == transitionId, "Transicao nao existe");
        _;
    }
    
    // Construtor
    constructor(
        bytes32 _id,
        string memory _name,
        string memory _description,
        bytes32 _initialState
    ) {
        id = _id;
        name = _name;
        description = _description;
        initialState = _initialState;
        currentState = _initialState;
        
        // Inicializar histórico
        stateHistory.push(_initialState);
        
        emit StateMachineInitialized(_id, _initialState);
    }
    
    // Funções para configuração
    
    /**
     * @dev Adiciona um novo estado à máquina de estados
     */
    function addState(
        bytes32 _id,
        string memory _name,
        string memory _description,
        bool _isFinal,
        bool _isError,
        bytes32[] memory _onEnterActions,
        bytes32[] memory _onExitActions
    ) external {
        require(states[_id].id != _id, "Estado ja existe");
        
        State memory newState = State({
            id: _id,
            name: _name,
            description: _description,
            isFinal: _isFinal,
            isError: _isError,
            onEnterActions: _onEnterActions,
            onExitActions: _onExitActions
        });
        
        states[_id] = newState;
    }
    
    /**
     * @dev Adiciona uma nova transição à máquina de estados
     */
    function addTransition(
        bytes32 _id,
        string memory _name,
        string memory _description,
        bytes32 _fromState,
        bytes32 _toState,
        bytes32[] memory _conditions,
        bytes32[] memory _actions
    ) external onlyExistingState(_fromState) onlyExistingState(_toState) {
        require(transitions[_id].id != _id, "Transicao ja existe");
        
        Transition memory newTransition = Transition({
            id: _id,
            name: _name,
            description: _description,
            fromState: _fromState,
            toState: _toState,
            conditions: _conditions,
            actions: _actions
        });
        
        transitions[_id] = newTransition;
        stateTransitions[_fromState].push(newTransition);
    }
    
    /**
     * @dev Registra um verificador de condição
     */
    function registerConditionVerifier(bytes32 _conditionId, address _verifier) external {
        require(_verifier != address(0), "Endereco invalido");
        conditionVerifiers[_conditionId] = _verifier;
    }
    
    /**
     * @dev Registra um executor de ação
     */
    function registerActionExecutor(bytes32 _actionId, address _executor) external {
        require(_executor != address(0), "Endereco invalido");
        actionExecutors[_actionId] = _executor;
    }
    
    // Funções para execução
    
    /**
     * @dev Tenta realizar uma transição específica
     */
    function tryTransition(bytes32 _transitionId, bytes calldata _data) external onlyExistingTransition(_transitionId) returns (bool) {
        Transition storage transition = transitions[_transitionId];
        
        // Verificar se a transição parte do estado atual
        require(transition.fromState == currentState, "Transicao invalida para o estado atual");
        
        // Verificar todas as condições
        for (uint256 i = 0; i < transition.conditions.length; i++) {
            bytes32 conditionId = transition.conditions[i];
            address verifier = conditionVerifiers[conditionId];
            
            require(verifier != address(0), "Verificador de condicao nao registrado");
            
            // Chamar o verificador de condição
            (bool success, bytes memory result) = verifier.call(_data);
            
            if (!success || !abi.decode(result, (bool))) {
                string memory reason = "Condicao falhou";
                if (result.length > 0) {
                    reason = abi.decode(result, (string));
                }
                
                emit ConditionFailed(_transitionId, conditionId, reason);
                return false;
            }
        }
        
        // Executar ações de saída do estado atual
        State storage currentStateObj = states[currentState];
        for (uint256 i = 0; i < currentStateObj.onExitActions.length; i++) {
            bytes32 actionId = currentStateObj.onExitActions[i];
            _executeAction(actionId, _transitionId, _data);
        }
        
        // Executar ações da transição
        for (uint256 i = 0; i < transition.actions.length; i++) {
            bytes32 actionId = transition.actions[i];
            _executeAction(actionId, _transitionId, _data);
        }
        
        // Registrar evento de transição
        bytes32 previousState = currentState;
        currentState = transition.toState;
        stateHistory.push(currentState);
        
        TransitionEvent memory event_ = TransitionEvent({
            timestamp: block.timestamp,
            fromState: previousState,
            toState: currentState,
            transitionId: _transitionId
        });
        
        transitionHistory.push(event_);
        
        // Executar ações de entrada do novo estado
        State storage newStateObj = states[currentState];
        for (uint256 i = 0; i < newStateObj.onEnterActions.length; i++) {
            bytes32 actionId = newStateObj.onEnterActions[i];
            _executeAction(actionId, _transitionId, _data);
        }
        
        emit StateChanged(previousState, currentState, _transitionId);
        return true;
    }
    
    /**
     * @dev Executa uma ação específica
     */
    function _executeAction(bytes32 _actionId, bytes32 _transitionId, bytes calldata _data) internal {
        address executor = actionExecutors[_actionId];
        
        if (executor == address(0)) {
            emit ActionExecuted(_transitionId, _actionId, false);
            return;
        }
        
        (bool success, ) = executor.call(_data);
        emit ActionExecuted(_transitionId, _actionId, success);
    }
    
    // Funções de consulta
    
    /**
     * @dev Retorna o estado atual
     */
    function getCurrentState() external view returns (bytes32) {
        return currentState;
    }
    
    /**
     * @dev Retorna informações do estado atual
     */
    function getCurrentStateInfo() external view returns (
        bytes32 id,
        string memory name,
        string memory description,
        bool isFinal,
        bool isError
    ) {
        State storage state = states[currentState];
        return (
            state.id,
            state.name,
            state.description,
            state.isFinal,
            state.isError
        );
    }
    
    /**
     * @dev Verifica se o estado atual é final
     */
    function isInFinalState() external view returns (bool) {
        return states[currentState].isFinal;
    }
    
    /**
     * @dev Verifica se o estado atual é de erro
     */
    function isInErrorState() external view returns (bool) {
        return states[currentState].isError;
    }
    
    /**
     * @dev Retorna o histórico de estados
     */
    function getStateHistory() external view returns (bytes32[] memory) {
        return stateHistory;
    }
    
    /**
     * @dev Retorna o número de transições possíveis a partir do estado atual
     */
    function getPossibleTransitionsCount() external view returns (uint256) {
        return stateTransitions[currentState].length;
    }
    
    /**
     * @dev Retorna uma transição possível a partir do estado atual pelo índice
     */
    function getPossibleTransition(uint256 index) external view returns (
        bytes32 id,
        string memory name,
        string memory description,
        bytes32 fromState,
        bytes32 toState
    ) {
        require(index < stateTransitions[currentState].length, "Indice invalido");
        
        Transition storage transition = stateTransitions[currentState][index];
        return (
            transition.id,
            transition.name,
            transition.description,
            transition.fromState,
            transition.toState
        );
    }
}
