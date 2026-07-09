probs = EEG.etc.ic_classification.ICLabel.classifications;
nIC = size(probs, 1);

rv = nan(nIC, 1);
for ic = 1:nIC
    if isfield(EEG, 'dipfit') && ...
            isfield(EEG.dipfit, 'model') && ...
            numel(EEG.dipfit.model) >= ic && ...
            isfield(EEG.dipfit.model(ic), 'rv') && ...
            ~isempty(EEG.dipfit.model(ic).rv)
        rv(ic) = EEG.dipfit.model(ic).rv * 100;
    end
end

Brain = probs(:,1) * 100;
Muscle = probs(:,2) * 100;
Eye = probs(:,3) * 100;
Heart = probs(:,4) * 100;
LineNoise = probs(:,5) * 100;
ChannelNoise = probs(:,6) * 100;
Other = probs(:,7) * 100;

IC = (1:nIC)';

Decision = strings(nIC,1);

for ic = 1:nIC
    if Brain(ic) >= 70 && rv(ic) < 20
        Decision(ic) = "Good / review";
    elseif Brain(ic) >= 50 && rv(ic) < 20
        Decision(ic) = "Possible / review";
    elseif Brain(ic) >= 70 && rv(ic) >= 20 && rv(ic) < 25
        Decision(ic) = "Possible / borderline";
    else
        Decision(ic) = "Not selected";
    end
end

T = table(IC, Brain, Muscle, Eye, Heart, LineNoise, ChannelNoise, Other, rv, Decision, ...
    'VariableNames', {'IC','Brain','Muscle','Eye','Heart','LineNoise','ChannelNoise','Other','RV_percent','Decision'});

T = T(T.Decision ~= "Not selected", :);

disp(T)