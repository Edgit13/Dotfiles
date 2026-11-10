function tree --wraps='command tree -I __pycache__' --description 'alias tree=command tree -I __pycache__'
    command tree -I __pycache__ $argv
end
