function retcode=code2file(xcell,fname)
% H1 line
%
% Syntax
% -------
% ::
%
% Inputs
% -------
%
% Outputs
% --------
%
% More About
% ------------
%
% Examples
% ---------
%
% See also: 


retcode=0;
if isempty(xcell)
    retcode=603; % empty cell
    return
end
default_output_name='out_';

output_list=default_output_name;
input_list='';
if iscell(xcell)
    [xout]=main_engine();
    xout=[{[default_output_name,'=[']};xout;{'];'}];
elseif isstruct(xcell)
    derivative_fields={'size','functions','map','partitions'};%,'maxcols','nnz_derivs'
    eval_fields={'code','argins','argouts'};
    if all(isfield(xcell,derivative_fields))
        [xout]=derivative_engine();
    elseif all(isfield(xcell,eval_fields))
        [xout]=eval_engine();
    else
        % then it must be a transition matrix
        [xout]=transition_matrix_engine();
    end
elseif isa(xcell,'function_handle')
    retcode=utils.code.code2file({xcell},fname);
    return
else
    error('first input must be a cell, a structure or a function handle')
end


if ~retcode
    % write to file
    %--------------
    if isempty(input_list)
        input_list='(~,~,~,~,~,~,~,~,~,~)';
    end
    
    fid=fopen([fname,'.m'],'w');
    fprintf(fid,'%s\n\n',['%% Code automagically generated by RISE on ',datestr(now)]);
    fprintf(fid,'%s\n\n',['function ',output_list,'=',fname,input_list]);
    
    for icod=1:numel(xout)
        if ~isempty(xout{icod})
            fprintf(fid,'%s\n\n',[xout{icod}]);
        end
    end
    fclose(fid);
end

    function [xout]=transition_matrix_engine()
        xstruct=xcell;
        chain_names=fieldnames(xstruct);
        is_loose_commit=any(strcmp(chain_names,parser.loose_commit()));
        xout={[default_output_name,'=struct();'];'Q=1;'};
        if is_loose_commit
            xout=[
                xout
                {'Qinit=1;'}
                ];
        end
        for iname=1:numel(chain_names)
            chain=chain_names{iname};
            xcell={xstruct.(chain)};
            [xout_i]=main_engine();
            xout=[
                xout
                [default_output_name,'.',chain,'=',xout_i{1},';']
                {['Q=kron(Q,',default_output_name,'.',chain,');']}
                ];
            if is_loose_commit && ~strcmp(chain,parser.loose_commit())
                xout=[
                    xout
                    {['Qinit=kron(Qinit,',default_output_name,'.',chain,');']}
                    ];
            end
        end
        xout=[
            xout
            {['[',default_output_name,'.Q,retcode]=utils.code.validate_transition_matrix(Q);']}
            {'if ~retcode'}
            ];
        if ~is_loose_commit
            xout=[
                xout
                {'Qinit=Q;'}
                ];
        end
        xout=[
            xout
            {['[',default_output_name,'.Qinit,retcode]=utils.code.validate_transition_matrix(Qinit);']}
            {'end'}
            ];
        output_list=['[',output_list,',retcode]'];
    end

    function [xout]=derivative_engine()
        tmp=xcell;
        order=numel(tmp);
        xout={};
        this_output_name=cellfun(@(x)x(~isspace(x)),...
            strcat({default_output_name},...
            num2str((1:order)')),'uniformOutput',false);
        prologue={};
        different_orders={'first','second','third','fourth','fifth',...
            'sixth','seventh','eigth','nineth','tenth'};
        end_prologue=0;
        for io=1:order
            [xout_io]=do_one_order(io);
            subfunc_name=sprintf('do_%s_order',different_orders{io});
            add_on={sprintf('if nargout >%0.0f',io-1)};
            end_prologue=end_prologue+1;
            prologue=[
                prologue
                add_on
                {[this_output_name{io},'=',subfunc_name,'();']}
                ];
            xout=[
                xout
                {sprintf('function %s=%s',default_output_name,[subfunc_name,'()'])}
                xout_io
                {[default_output_name,'=sparse(',default_output_name,');']}
                {'end'}
                ];
        end
        xout=[
            prologue
            repmat({'end'},end_prologue,1)% closing the if nargout > n-1
            xout
            {'end'}
            ];
        output_list=cell2mat(strcat(this_output_name(:)',','));
        output_list=['[',output_list(1:end-1),']'];
        
        function [xout]=do_one_order(oo)
            xcell=tmp(oo).functions;
            % output initialization
            xxx=sprintf('%s=zeros(%0.0f',default_output_name,tmp(oo).size(1));
            for icol=2:numel(tmp(oo).size)
                xxx=[xxx,',',sprintf('%0.0f',tmp(oo).size(icol))]; %#ok<*AGROW>
            end
            xxx=[xxx,');'];
            [xout]=main_engine();
            if ~isempty(xcell)
                rows_check=tmp(oo).rows_check;
                for irows=1:size(xcell,1)
                    if ~isempty(xout{irows})
                        strcols=stringify_indexes(tmp(oo).map{irows});
                        xout{irows}=sprintf('%s(%0.0f,%s)=%s;',...
                            default_output_name,rows_check(irows),...
                            strcols,xout{irows});
                    end
                end
                % expand output
                xout{irows+1}=sprintf('%s=%s(:,%s);',...
                    default_output_name,default_output_name,...
                    stringify_indexes(tmp(oo).partitions));
                % add initialization
                xout=[{xxx};xout];
            else
                xout={xxx};
            end
        end
    end

    function strcols=stringify_indexes(indexes)
        n=numel(indexes);
        strcols=sprintf('%0.0f',indexes(1));
        for ind=2:n
            strcols=[strcols,',',sprintf('%0.0f',indexes(ind))];
        end
        if n>1
            strcols=['[',strcols,']'];
        end
    end

    function [xout]=main_engine()
        n=numel(xcell);
        xout=xcell;
        entry_gate='';
        for item=1:n
            if ~isempty(xcell{item})
                if ~isa(xcell{item},'function_handle')
                    error('all elements in xcell should be function handles')
                end
                xout{item}=func2str(xcell{item});
                if isempty(entry_gate)
                    right_parenth=find(xout{item}==')',1,'first');
                    entry_gate=xout{item}(1:right_parenth);
                end
            end
        end
        xout=strrep(xout,entry_gate,'');
        if isempty(input_list)
            input_list=strrep(entry_gate,'@','');
        end
    end

    function [code]=eval_engine()
        if isempty(input_list)
            input_list=cell2mat(strcat(xcell.argins,','));
            input_list=['(',input_list(1:end-1),')'];
        end
        
        output_list=cell2mat(strcat(xcell.argouts,','));
        output_list=['[',output_list(1:end-1),']'];
        
        if isempty(xcell.code)
            code={};
            retcode=603;
        else
            code=regexp(xcell.code,';','split');
            % replace the nargout_ which is used in evaluation with nargout, which is
            % used in the normal function
            code=regexprep(code,'(?<!\w+)narg(out|in)_(?!\w+)','narg$1');
            
            code=code(:);
            code=code(cell2mat(cellfun(@(x)~isempty(x),code,'uniformOutput',false)));
            code=strcat(code,';');
        end
    end
end
