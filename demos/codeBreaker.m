% demo of Bayesian optimization for "code breaking"


function bayesianCodeBreakerSimple()



    function prior = makeCodePrior(L, A, code)
        % set code(i)  = 0 if unknown (uniform prior for ci)
        % set code(i) in {1,..,A} to use delta function for that slot
        cs = ind2subv(A*ones(1,L), 1:A^L);
        prior = ones(1, A^L);
        for i=1:A^L
            for l=1:L
             if (code(l) > 0) && (cs(i,l) ~= code(l)) 
                    prior(i) = 0;
             end
            end
        end
        prior = normalize(prior);
    end

function CPT = makeLikelihoodCPT(L, A)
        % CPT(x,c,y) = p(y|x,c)
        nstr = A^L;
        CPT = zeros(nstr, nstr, L+1);
        sz = A*ones(1,L);
        for xndx = 1:nstr
            x = ind2subv(sz, xndx);
            for cndx = 1:nstr
                c = ind2subv(sz, cndx);
                h = hammingDistance(x, c);
                y = h + 1;
                CPT(xndx, cndx, y) = 1.0;
            end
        end
end

 

    function Fmodel = makeSurrogate(L, A, likelihoodCPT, codePrior)
        % likelihoodCPT(x, c, y) = p(y| c, x)
        % codePrior(c) = prob(code=c)
        % predictiveCPT(xndx, y) = sum_c p(y | x=xnd, c) * codeDist(c)
        nyvals = L+1;
        predictiveCPT = zeros(A^L, nyvals);
        for yndx=1:nyvals
            predictiveCPT(:, yndx) = likelihoodCPT(:,:,yndx) * codePrior(:);
        end
        Fprob = reshape(predictiveCPT, [A*ones(1,L), L+1]);
        Fdomain = ind2subv(A*ones(1,L), 1:A^L);
        Frange = 0:L;
        Fmodel = structure(Fprob, likelihoodCPT, codePrior, predictiveCPT, L, A, Fdomain, Frange);
    end  

    function Fmodel = updateSurrogate(Fmodel, x, y)
        L = Fmodel.L; A = Fmodel.A;
        xndx = subv2ind(A*ones(1,L), x);
        yndx = y+1;
        likCPT = Fmodel.likelihoodCPT;
        lik = squeeze(likCPT(xndx, :, yndx));
        codePost = normalize(lik .* Fmodel.codePrior);
        Fmodel = makeSurrogate(L, A, likCPT, codePost);
    end



     function e = expectedValue(Fmodel, x)
            L = Fmodel.L; A = Fmodel.A; 
            assert(L == length(x));
            ndx = subv2ind(A*ones(1,L), x);
            prob = reshape(Fmodel.Fprob, [A^L, length(Fmodel.Frange)]);
            e = sum(prob(ndx, :) .* Fmodel.Frange);
     end

  function e = expectedImprovement(Fmodel, x, thresh)
            L = Fmodel.L; A = Fmodel.A; 
            assert(L == length(x));
            ndx = subv2ind(A*ones(1,L), x);
            prob = reshape(Fmodel.Fprob, [A^L, length(Fmodel.Frange)]);
            probGivenX = prob(ndx, :);
            fn = @(y) max(0, (thresh-y)); % if y < thresh, we improve
            ys = Fmodel.Frange;
            e = 0;
            for i=1:length(ys)
                e = e + probGivenX(i)*fn(ys(i));
            end
     end

    function dispSurrogate(Fmodel, trueCode, varargin)
        [str, doPlot, drawLines, incumbentVal, showAll] = process_options(varargin, ...
            'str', '', 'doPlot', true, 'drawLines',false, ...
            'incumbentVal', 0, 'showAll', false);
        L = Fmodel.L; A = Fmodel.A;
    xs = Fmodel.Fdomain;
    e = applyFun(xs, @(x) expectedValue(Fmodel, x));
    eic = applyFun(xs, @(x) expectedImprovement(Fmodel, x, incumbentVal));
    o = applyFun(xs, @(x) hammingDistance(x, trueCode));
    [ndx] = argmaxima(eic);
    nmin = length(ndx);
    if doPlot
        Nstr = length(e); 
        figure; 
        if drawLines
            plot(1:Nstr, e, 'r-', 1:Nstr, eic, 'g--', 1:Nstr, o, 'b:', 'linewidth', 2);
        else
            plot(1:Nstr, e, 'rx', 1:Nstr, eic, 'g*', 1:Nstr, o, 'bo', 'linewidth', 2);
        end
        set(gca, 'ylim', [-0.1 L+0.1]);
        legend('expected', 'eic', 'true', 'location', 'southeast')
        title(str);
        set(gca, 'xtick', ndx);
        args = cell(1, nmin);
        for i=1:nmin
            args{i} = num2str(xs(ndx(i),:));
        end
        xticklabelRot(args, 45, 8);
    end

    %{
    if showAll
        ndx = 1:length(o);
    else
        [ndx] = argmaxima(eic);
    end
    nmin = length(ndx);
    separator = repmat('|', nmin, 1);
    disp(str)
    disp('args, expected, eic, objective');
    evals = e(ndx); eicvals = eic(ndx); ovals = o(ndx);
    disp([num2str(xs(ndx,:)), separator, num2str(evals(:)), ...
            separator, num2str(eicvals(:)), separator, num2str(ovals(:))])
    %}
     
    end



%% Generic code
    function vals = applyFun(args, fn)
        % vals(i) = fn(args(i,:))
        nrows = size(args, 1);
        vals = zeros(1, nrows);
        for i=1:nrows
            vals(i) = fn(args(i,:));
        end
    end
        

    function [ndx, vals] = argminima(scores)
        m = min(scores);
        ndx = find(scores==m);
        vals = scores(ndx); % N copies of the value m
    end

 function [ndx, vals] = argmaxima(scores)
        m = max(scores);
        ndx = find(scores==m);
        vals = scores(ndx); % N copies of the value m
    end


    function h = hammingDistance(x, c)
        h = sum(x ~= c);
    end

  function saveFigure(fname)
         printFolder = '/home/kpmurphy/github/pmtk3/figures';
         format = 'png';
         fname = sprintf('%s/%s.%s', printFolder, fname, format);
        fprintf('printing to %s\n', fname);
         print(gcf, '-dpng', fname);
    end


%% Testing code

    function test()
 L = 2; A =3;
        code = [1,2];
    codePriorHint = [0,2];
    codePrior = makeCodePrior(L, A, codePriorHint);
    dispcpt(codePrior)
    keyboard
    end

    function testSurrogate()
        L = 3; A =4;
        code = [1,1,1];
    codePriorHint = [0,0,0];
    codePrior = makeCodePrior(L, A, codePriorHint);
    
    likCPT = makeLikelihoodCPT(L, A);
    surrogate = makeSurrogate(L, A, likCPT, codePrior);
    incumbentVal = max(surrogate.Frange);
    dispSurrogate(surrogate, code, 'str', 'unif', 'incumbentVal', incumbentVal)
  
    x=[1,1,2]; y = hammingDistance(x, code);
    incumbentVal = min(y, incumbentVal);
    surrogate = updateSurrogate(surrogate, x, y);
    dispSurrogate(surrogate, code, 'str', 'unif+f(112)', 'incumbentVal', incumbentVal)
    
    x=[1,1,4]; y = hammingDistance(x, code);
    incumbentVal = min(y, incumbentVal);
    surrogate = updateSurrogate(surrogate, x, y);
    dispSurrogate(surrogate, code, 'str', 'unif+f(112)+f(114)', 'incumbentVal', incumbentVal)
    
    x=[1,1,3]; y = hammingDistance(x, code);
    incumbentVal = min(y, incumbentVal);
    surrogate = updateSurrogate(surrogate, x, y);
    dispSurrogate(surrogate, code, 'str', 'unif+f(112)+f(114)+f(113)', 'incumbentVal', incumbentVal)
    end

   
    

%% Main

test()
%testSurrogate()


end
